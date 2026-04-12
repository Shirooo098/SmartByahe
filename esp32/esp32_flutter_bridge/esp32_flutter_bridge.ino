#include <WiFi.h>
#include <WebSocketsServer.h>
#include "HX711.h"
#include <TinyGPS++.h>

// High-precision weight tracking
#define SAMPLES_PER_READ 50  // Increase samples for better precision
#define EMA_ALPHA 0.05f      // Tighter EMA (0.05 = 5% new, 95% old) for high sensitivity
#define GPS_AVG_SIZE 5
#define WEIGHT_DELTA_THRESHOLD 0.5f       // Alert if weight changes by more than 0.5g
#define MIN_WEIGHT_G_SENSITIVE 0.5f       // Ultra-low noise floor for clay detection
#define BASELINE_MIN_MODEL_WEIGHT 100.0f  // Minimum weight considered as bus model baseline
#define BASELINE_SAMPLE_COUNT 10          // Number of startup readings to average for baseline
#define BASELINE_STABLE_THRESHOLD 5.0f    // Require stable raw reading before capture
#define BASELINE_STABLE_READS 5           // Number of stable startup samples required

// FreeRTOS task priorities and stack sizes
#define SENSOR_TASK_PRIORITY 1
#define WEBSOCKET_TASK_PRIORITY 2
#define SENSOR_STACK_SIZE 4096
#define WEBSOCKET_STACK_SIZE 4096

// Simple auth token (change in production)
const char *AUTH_TOKEN = "smartbyahe2026";

const char *kHotspotSsid = "MNDZ1";
const char *kHotspotPassword = "08091125#OAkc";
const uint16_t kWebSocketPort = 81;

const unsigned long kSendIntervalMs = 1000;
unsigned long lastSendMs = 0;

#define FRONT_DT 4
#define FRONT_SCK 5
#define BACK_DT 18
#define BACK_SCK 19

#define FRONT_CAL 433.57
#define BACK_CAL 434.68

#ifndef MIN_WEIGHT_G
#define MIN_WEIGHT_G 50
#endif

#define MAX_WEIGHT_GRAMS 4000.0f
#define IMBALANCE_THRESHOLD_PCT 60.0f
#define MIN_WEIGHT_FOR_BALANCE_G 200.0f

#define USE_STATIC_IP 0
#if USE_STATIC_IP
IPAddress kStaticIp(192, 168, 43, 100);
IPAddress kStaticGateway(192, 168, 43, 1);
IPAddress kStaticSubnet(255, 255, 255, 0);
IPAddress kStaticDns(8, 8, 8, 8);
#endif

#define GPS_RX_PIN 16
#define GPS_TX_PIN 17
#define GPS_BAUD 9600

bool wsClientConnected = false;
float frontWeight = 0.0f;
float backWeight = 0.0f;
float totalWeight = 0.0f;
float frontPct = 0.0f;
float backPct = 0.0f;
bool gpsValid = false;
double latitude = 0.0;
double longitude = 0.0;
bool hx711FrontReady = false;
bool hx711BackReady = false;
int gpsSatellites = 0;

float frontScaleFactor = FRONT_CAL;
float backScaleFactor = BACK_CAL;

// EMA filtered weights
float frontWeightFiltered = 0.0f;
float backWeightFiltered = 0.0f;

// Offset/reference weights (calibrated with bus model loaded)
float frontOffsetWeight = 0.0f;
float backOffsetWeight = 0.0f;

// Startup baseline capture states
bool startupBaselineCaptured = false;
int baselineSampleCount = 0;
int baselineStableCount = 0;
float baselineFrontSum = 0.0f;
float baselineBackSum = 0.0f;
float baselineFrontPrev = 0.0f;
float baselineBackPrev = 0.0f;

// Previous weights for delta detection
float frontWeightPrev = 0.0f;
float backWeightPrev = 0.0f;
bool frontWeightChanged = false;
bool backWeightChanged = false;
float frontWeightDelta = 0.0f;
float backWeightDelta = 0.0f;

// High-precision mode flag
bool highPrecisionMode = true;

// GPS averaging buffers
double latBuffer[GPS_AVG_SIZE];
double lngBuffer[GPS_AVG_SIZE];
int gpsBufferIndex = 0;
bool gpsBufferFull = false;

// Task handles
TaskHandle_t sensorTaskHandle;
TaskHandle_t websocketTaskHandle;

// Mutex for shared data
SemaphoreHandle_t dataMutex;

String loadStatusString(float totalG, float frontPct, float backPct) {
  if (totalG >= MAX_WEIGHT_GRAMS) return "OVERLOAD";
  if (totalG >= MIN_WEIGHT_FOR_BALANCE_G) {
    if (frontPct > IMBALANCE_THRESHOLD_PCT) return "IMBALANCE_FRONT";
    if (backPct > IMBALANCE_THRESHOLD_PCT) return "IMBALANCE_BACK";
  }
  return "NORMAL";
}

WebSocketsServer webSocket(kWebSocketPort);
HX711 frontScale;
HX711 backScale;
TinyGPSPlus gps;

// Sensor task: handles sensor updates
void sensorTask(void *pvParameters) {
  while (true) {
    xSemaphoreTake(dataMutex, portMAX_DELAY);
    updateSensors();
    xSemaphoreGive(dataMutex);
    vTaskDelay(pdMS_TO_TICKS(1000));  // Update every 1s
  }
}

// WebSocket task: handles WebSocket and sending
void websocketTask(void *pvParameters) {
  while (true) {
    webSocket.loop();
    unsigned long now = millis();
    if (now - lastSendMs >= kSendIntervalMs) {
      lastSendMs = now;
      xSemaphoreTake(dataMutex, portMAX_DELAY);
      sendStatus();
      xSemaphoreGive(dataMutex);
    }
    vTaskDelay(pdMS_TO_TICKS(100));  // Check frequently
  }
}

void updateSensors() {
  while (Serial2.available()) {
    gps.encode(Serial2.read());
  }

  if (gps.location.isValid()) {
    // Add to GPS buffer for averaging
    latBuffer[gpsBufferIndex] = gps.location.lat();
    lngBuffer[gpsBufferIndex] = gps.location.lng();
    gpsBufferIndex = (gpsBufferIndex + 1) % GPS_AVG_SIZE;
    if (gpsBufferIndex == 0) gpsBufferFull = true;

    // Average GPS if buffer full
    if (gpsBufferFull) {
      double latSum = 0, lngSum = 0;
      for (int i = 0; i < GPS_AVG_SIZE; i++) {
        latSum += latBuffer[i];
        lngSum += lngBuffer[i];
      }
      latitude = latSum / GPS_AVG_SIZE;
      longitude = lngSum / GPS_AVG_SIZE;
    } else {
      latitude = gps.location.lat();
      longitude = gps.location.lng();
    }
  }
  gpsValid = gps.location.isValid();
  gpsSatellites = gps.satellites.isValid() ? (int)gps.satellites.value() : 0;

  const bool frontOk = frontScale.is_ready();
  const bool backOk = backScale.is_ready();
  hx711FrontReady = frontOk;
  hx711BackReady = backOk;

  // Use high-precision sampling (50 samples vs 10)
  int samples = highPrecisionMode ? SAMPLES_PER_READ : 10;
  float rawFront = frontOk ? frontScale.get_units(samples) : 0.0f;
  float rawBack = backOk ? backScale.get_units(samples) : 0.0f;

  // Capture bus baseline at startup if not already done
  if (!startupBaselineCaptured) {
    float totalRaw = rawFront + rawBack;
    if (totalRaw >= BASELINE_MIN_MODEL_WEIGHT) {
      bool stable = (baselineSampleCount == 0) || (fabs(rawFront - baselineFrontPrev) < BASELINE_STABLE_THRESHOLD && fabs(rawBack - baselineBackPrev) < BASELINE_STABLE_THRESHOLD);

      if (stable) {
        baselineStableCount++;
        baselineFrontSum += rawFront;
        baselineBackSum += rawBack;
        baselineSampleCount++;
      } else {
        baselineStableCount = 0;
        baselineSampleCount = 0;
        baselineFrontSum = 0.0f;
        baselineBackSum = 0.0f;
      }

      baselineFrontPrev = rawFront;
      baselineBackPrev = rawBack;

      if (baselineStableCount >= BASELINE_STABLE_READS && baselineSampleCount >= BASELINE_SAMPLE_COUNT) {
        frontOffsetWeight = baselineFrontSum / baselineSampleCount;
        backOffsetWeight = baselineBackSum / baselineSampleCount;
        startupBaselineCaptured = true;
        frontWeightPrev = 0.0f;
        backWeightPrev = 0.0f;
        Serial.printf("✓ Startup baseline LOCKED: front %.1f g, back %.1f g\n", frontOffsetWeight, backOffsetWeight);
      }
    } else {
      baselineStableCount = 0;
      baselineSampleCount = 0;
      baselineFrontSum = 0.0f;
      baselineBackSum = 0.0f;
      Serial.println("Baseline pending... (need weight >= 100g to start)");
    }
  }

  // Subtract offset for net weight inside bus after baseline capture or manual offset
  if (startupBaselineCaptured || frontOffsetWeight != 0.0f || backOffsetWeight != 0.0f) {
    rawFront -= frontOffsetWeight;
    rawBack -= backOffsetWeight;
  }

  // Apply EMA filtering
  if (frontWeightFiltered == 0.0f) frontWeightFiltered = rawFront;  // Initialize
  else frontWeightFiltered = EMA_ALPHA * rawFront + (1 - EMA_ALPHA) * frontWeightFiltered;

  if (backWeightFiltered == 0.0f) backWeightFiltered = rawBack;
  else backWeightFiltered = EMA_ALPHA * rawBack + (1 - EMA_ALPHA) * backWeightFiltered;

  // Apply threshold based on mode
  float threshold = highPrecisionMode ? WEIGHT_DELTA_THRESHOLD : MIN_WEIGHT_G;
  frontWeight = (frontWeightFiltered < 0.0f) ? 0.0f : frontWeightFiltered;
  backWeight = (backWeightFiltered < 0.0f) ? 0.0f : backWeightFiltered;

  // Track weight deltas for change detection
  frontWeightDelta = fabs(frontWeight - frontWeightPrev);
  backWeightDelta = fabs(backWeight - backWeightPrev);
  frontWeightChanged = (frontWeightDelta > threshold);
  backWeightChanged = (backWeightDelta > threshold);
  frontWeightPrev = frontWeight;
  backWeightPrev = backWeight;

  totalWeight = frontWeight + backWeight;
  if (totalWeight > 0) {
    frontPct = (frontWeight / totalWeight) * 100.0f;
    backPct = (backWeight / totalWeight) * 100.0f;
  } else {
    frontPct = 0.0f;
    backPct = 0.0f;
  }
}

void sendStatus() {
  String status = loadStatusString(totalWeight, frontPct, backPct);

  // ★ speed_kmh field removed from JSON
  String payload = "{\"type\":\"telemetry\"";
  payload += ",\"weight_g\":" + String(totalWeight, 1);
  payload += ",\"front_g\":" + String(frontWeight, 1);
  payload += ",\"back_g\":" + String(backWeight, 1);
  payload += ",\"front_pct\":" + String(frontPct, 1);
  payload += ",\"back_pct\":" + String(backPct, 1);
  payload += ",\"status\":\"" + status + "\"";
  payload += ",\"satellites\":" + String(gpsSatellites);
  payload += ",\"latitude\":" + String(latitude, 6);
  payload += ",\"longitude\":" + String(longitude, 6);
  payload += ",\"gps_valid\":" + String(gpsValid ? "true" : "false");
  payload += ",\"front_ready\":" + String(hx711FrontReady ? "true" : "false");
  payload += ",\"back_ready\":" + String(hx711BackReady ? "true" : "false");
  payload += ",\"front_delta_g\":" + String(frontWeightDelta, 1);
  payload += ",\"back_delta_g\":" + String(backWeightDelta, 1);
  payload += ",\"front_changed\":" + String(frontWeightChanged ? "true" : "false");
  payload += ",\"back_changed\":" + String(backWeightChanged ? "true" : "false");
  payload += ",\"precision_mode\":\"" + String(highPrecisionMode ? "high" : "normal") + "\"";
  payload += ",\"baseline_captured\":" + String(startupBaselineCaptured ? "true" : "false");
  payload += ",\"has_hx711_lib\":true";
  payload += ",\"has_gps_lib\":true";
  payload += "}";

  Serial.println(payload);
  if (wsClientConnected) {
    webSocket.broadcastTXT(payload);
  }
}

void setScaleFactor(HX711 &scale, float &scaleFactor, float newFactor, const char *name) {
  scaleFactor = newFactor;
  scale.set_scale(scaleFactor);
  Serial.printf("%s scale factor updated to %.2f\n", name, scaleFactor);
}

void calibrateScale(HX711 &scale, float &scaleFactor, const char *name, float knownGrams) {
  if (!scale.is_ready()) {
    Serial.printf("%s HX711 not ready, cannot calibrate.\n", name);
    return;
  }

  Serial.printf("Taring %s scale before calibration...\n", name);
  scale.tare(10);
  delay(500);

  Serial.printf("Place a known %.2fg weight on the %s scale and press Enter...\n", knownGrams, name);
  while (!Serial.available()) {
    delay(100);
  }
  Serial.readStringUntil('\n');

  float currentReading = scale.get_units(20);
  if (currentReading <= 0.0f) {
    Serial.printf("%s current reading is %.2f after tare. Check the weight and wiring.\n", name, currentReading);
    return;
  }

  float newFactor = scaleFactor * (currentReading / knownGrams);
  if (newFactor <= 0.0f) {
    Serial.printf("Invalid new %s scale factor computed.\n", name);
    return;
  }

  setScaleFactor(scale, scaleFactor, newFactor, name);
  Serial.printf("Calibration complete: %s should now read %.2f g for the known weight.\n", name, knownGrams);
}

void printCalibrationHelp() {
  Serial.println("Calibration commands:");
  Serial.println("  cal front 907.185   -> calibrate front scale using 2 lb weight");
  Serial.println("  cal back 907.185    -> calibrate back scale using 2 lb weight");
  Serial.println("  setcal front 434.68 -> set front scale factor directly");
  Serial.println("  setcal back 434.68  -> set back scale factor directly");
  Serial.println("  tare front          -> tare front scale");
  Serial.println("  tare back           -> tare back scale");
  Serial.println("  tare all            -> tare both scales");
  Serial.println("  setoffset front     -> set front offset (bus weight reference)");
  Serial.println("  setoffset back      -> set back offset (bus weight reference)");
  Serial.println("  setoffset all       -> set both offsets");
  Serial.println("  precision high      -> enable high-precision clay detection");
  Serial.println("  precision normal    -> disable high-precision mode");
  Serial.println("  status              -> show current settings and live values");
  Serial.println("  help                -> print this command list");
}

void printStatus() {
  Serial.printf("Front scale factor: %.2f\n", frontScaleFactor);
  Serial.printf("Back scale factor: %.2f\n", backScaleFactor);
  Serial.printf("Front offset: %.1fg, Back offset: %.1fg\n", frontOffsetWeight, backOffsetWeight);
  Serial.printf("Baseline captured: %s\n", startupBaselineCaptured ? "YES" : "NO");
  Serial.printf("Front: %.1fg (Δ%.1fg), Back: %.1fg (Δ%.1fg)\n", frontWeight, frontWeightDelta, backWeight, backWeightDelta);
  Serial.printf("Total: %.1fg, Front %%: %.1f, Back %%: %.1f\n", totalWeight, frontPct, backPct);
  Serial.printf("Status: %s, Precision Mode: %s\n", loadStatusString(totalWeight, frontPct, backPct).c_str(), highPrecisionMode ? "HIGH" : "NORMAL");
}

void processSerialCommands() {
  if (!Serial.available()) return;

  String line = Serial.readStringUntil('\n');
  line.trim();
  if (line.length() == 0) return;

  if (line.equalsIgnoreCase("help")) {
    printCalibrationHelp();
    return;
  }

  if (line.startsWith("cal ")) {
    if (line.startsWith("cal front ")) {
      float grams = line.substring(10).toFloat();
      if (grams <= 0) grams = 907.185f;
      calibrateScale(frontScale, frontScaleFactor, "Front", grams);
    } else if (line.startsWith("cal back ")) {
      float grams = line.substring(9).toFloat();
      if (grams <= 0) grams = 907.185f;
      calibrateScale(backScale, backScaleFactor, "Back", grams);
    } else {
      Serial.println("Unknown cal command. Use 'help' for syntax.");
    }
    return;
  }

  if (line.startsWith("setcal ")) {
    if (line.startsWith("setcal front ")) {
      float factor = line.substring(13).toFloat();
      if (factor > 0) setScaleFactor(frontScale, frontScaleFactor, factor, "Front");
    } else if (line.startsWith("setcal back ")) {
      float factor = line.substring(12).toFloat();
      if (factor > 0) setScaleFactor(backScale, backScaleFactor, factor, "Back");
    } else {
      Serial.println("Unknown setcal command. Use 'help' for syntax.");
    }
    return;
  }

  if (line.equalsIgnoreCase("tare front")) {
    if (frontScale.is_ready()) frontScale.tare(10);
    Serial.println("Front scale tared.");
    return;
  }
  if (line.equalsIgnoreCase("tare back")) {
    if (backScale.is_ready()) backScale.tare(10);
    Serial.println("Back scale tared.");
    return;
  }
  if (line.equalsIgnoreCase("tare all")) {
    if (frontScale.is_ready()) frontScale.tare(10);
    if (backScale.is_ready()) backScale.tare(10);
    Serial.println("Both scales tared.");
    return;
  }
  if (line.equalsIgnoreCase("status")) {
    printStatus();
    return;
  }

  if (line.startsWith("setoffset ")) {
    if (line.startsWith("setoffset front")) {
      frontOffsetWeight = frontWeightFiltered;
      Serial.printf("Front offset set to %.2f g\n", frontOffsetWeight);
    } else if (line.startsWith("setoffset back")) {
      backOffsetWeight = backWeightFiltered;
      Serial.printf("Back offset set to %.2f g\n", backOffsetWeight);
    } else if (line.startsWith("setoffset all")) {
      frontOffsetWeight = frontWeightFiltered;
      backOffsetWeight = backWeightFiltered;
      Serial.printf("Offsets set: Front=%.2f g, Back=%.2f g\n", frontOffsetWeight, backOffsetWeight);
    }
    return;
  }

  if (line.startsWith("precision ")) {
    if (line.startsWith("precision high")) {
      highPrecisionMode = true;
      Serial.println("High-precision mode ENABLED (50 samples/read, ultra-sensitive)");
    } else if (line.startsWith("precision normal")) {
      highPrecisionMode = false;
      Serial.println("High-precision mode DISABLED (normal sensitivity)");
    }
    return;
  }

  Serial.println("Unknown command. Type 'help'.");
}

void onWebSocketEvent(uint8_t clientNum, WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      wsClientConnected = true;
      Serial.printf("WS client connected: %u\n", clientNum);
      break;
    case WStype_DISCONNECTED:
      wsClientConnected = (webSocket.connectedClients() > 0);
      Serial.printf("WS client disconnected: %u\n", clientNum);
      break;
    case WStype_TEXT:
      // Simple auth check
      if (length > 0) {
        String msg = String((char *)payload);
        if (msg.startsWith(AUTH_TOKEN)) {
          Serial.println("Auth successful");
          // Check for tare command
          if (msg.indexOf("tare") != -1) {
            xSemaphoreTake(dataMutex, portMAX_DELAY);
            if (frontScale.is_ready()) frontScale.tare(10);
            if (backScale.is_ready()) backScale.tare(10);
            frontWeightFiltered = 0.0f;  // Reset filter
            backWeightFiltered = 0.0f;
            xSemaphoreGive(dataMutex);
            Serial.println("Tared scales");
          }
        } else {
          Serial.println("Auth failed");
          webSocket.disconnect(clientNum);
        }
      }
      break;
    default:
      break;
  }
}

void connectToHotspot() {
  WiFi.mode(WIFI_STA);
#if USE_STATIC_IP
  if (!WiFi.config(kStaticIp, kStaticGateway, kStaticSubnet, kStaticDns)) {
    Serial.println("WiFi.config failed — falling back to DHCP");
  } else {
    Serial.println("Static IP configured.");
  }
#endif
  WiFi.begin(kHotspotSsid, kHotspotPassword);

  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    updateSensors();
    delay(100);
    Serial.print(".");
  }
  Serial.println();
  Serial.println("WiFi connected.");
  Serial.print("ESP32 IP: ");
  Serial.println(WiFi.localIP());
  Serial.print("Flutter connect to: ws://");
  Serial.print(WiFi.localIP());
  Serial.print(":");
  Serial.println(kWebSocketPort);
}

void setup() {
  Serial.begin(115200);
  delay(300);

  Serial2.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  Serial.println("GPS: Serial2 started (NEO-6M TX->GPIO16, RX->GPIO17)");

  delay(500);

  frontScale.begin(FRONT_DT, FRONT_SCK);
  frontScale.set_scale(frontScaleFactor);
  backScale.begin(BACK_DT, BACK_SCK);
  backScale.set_scale(backScaleFactor);

  unsigned long t0 = millis();
  while (!frontScale.is_ready() && millis() - t0 < 5000) delay(10);
  if (frontScale.is_ready()) {
    Serial.println("Front HX711: OK");
  } else {
    Serial.println("Front HX711: NOT READY — check DT/SCK/power");
  }

  t0 = millis();
  while (!backScale.is_ready() && millis() - t0 < 5000) delay(10);
  if (backScale.is_ready()) {
    Serial.println("Back HX711: OK");
  } else {
    Serial.println("Back HX711: NOT READY — check DT/SCK/power");
  }

  connectToHotspot();
  webSocket.begin();
  webSocket.onEvent(onWebSocketEvent);

  // Create mutex for shared data
  dataMutex = xSemaphoreCreateMutex();

  // Create FreeRTOS tasks
  xTaskCreate(sensorTask, "SensorTask", SENSOR_STACK_SIZE, NULL, SENSOR_TASK_PRIORITY, &sensorTaskHandle);
  xTaskCreate(websocketTask, "WebSocketTask", WEBSOCKET_STACK_SIZE, NULL, WEBSOCKET_TASK_PRIORITY, &websocketTaskHandle);

  Serial.println("ESP32 bridge ready with multithreading.");
}

void loop() {
  // Tasks handle everything; loop can be empty or used for monitoring
  processSerialCommands();
  vTaskDelay(pdMS_TO_TICKS(200));  // Idle delay
}