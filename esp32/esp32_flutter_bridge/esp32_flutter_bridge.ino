// Bus weight monitor — ESP32 + HX711 ×2 + NEO-6M GPS
// Measures total weight only. Overload above 4 kg.

#include <WiFi.h>
#include <WebSocketsServer.h>
#include <HTTPClient.h>
#include "HX711.h"
#include <TinyGPS++.h>

// ── Config ────────────────────────────────────────────────────────────────────
const char*    kSsid      = "MNDZ1";  // Change to your phone's hotspot name
const char*    kPassword  = "08091125#OAkc";  // Change to your hotspot password
const char*    kAuthToken = "smartbyahe2026";
const uint16_t kWsPort    = 81;
const char*    kBackendUrl = "http://192.168.68.105:8000/gps";  // PC/backend IP on hotspot


#define FRONT_DT   4
#define FRONT_SCK  5
#define BACK_DT    18
#define BACK_SCK   19
#define FRONT_CAL  433.57f
#define BACK_CAL   434.68f

#define GPS_RX_PIN 16
#define GPS_TX_PIN 17
#define GPS_BAUD   9600

// Starting point (from GPS screenshot)
const float START_LAT = 14.64142f;
const float START_LNG = 121.09264f;
const float START_RADIUS = 150.0f;  // meters

// Finish: LRT-2 Marikina-Pasig Station
// 1800 Marikina-Infanta Hwy, San Roque, Marikina
const float FINISH_LAT = 14.620387f;
const float FINISH_LNG = 121.100275f;
const float FINISH_RADIUS = 150.0f;  // meters

#define MAX_WEIGHT_G     100.0f
#define EMA_ALPHA        0.3f
#define SAMPLES_PER_READ 10
#define DEADBAND_G       2.0f

const unsigned long kSendIntervalMs = 1000;

enum TripPhase : uint8_t {
  AT_START = 0,
  DEPARTED_START = 1,
  EN_ROUTE = 2,
  ARRIVED_FINISH = 3,
};

TripPhase gTripPhase = AT_START;
TripPhase gCandidatePhase = AT_START;
uint8_t gStablePhaseReads = 0;

const int   kMinSatellitesForGeofence = 4;
const float kExitHysteresisMeters = 30.0f;
const uint8_t kStableReadsNeeded = 3;

const char* phaseToString(TripPhase phase) {
  switch (phase) {
    case AT_START: return "AT_START";
    case DEPARTED_START: return "DEPARTED_START";
    case EN_ROUTE: return "EN_ROUTE";
    case ARRIVED_FINISH: return "ARRIVED_FINISH";
    default: return "UNKNOWN";
  }
}

float distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const double r = 6371000.0;
  const double dLat = radians(lat2 - lat1);
  const double dLng = radians(lng2 - lng1);
  const double a = sin(dLat / 2.0) * sin(dLat / 2.0) +
                   cos(radians(lat1)) * cos(radians(lat2)) *
                   sin(dLng / 2.0) * sin(dLng / 2.0);
  const double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
  return (float)(r * c);
}

TripPhase computePhase(float distStart, float distFinish, TripPhase current) {
  const float startExitRadius = START_RADIUS + kExitHysteresisMeters;

  if (distFinish <= FINISH_RADIUS) {
    return ARRIVED_FINISH;
  }
  if (distStart <= START_RADIUS) {
    return AT_START;
  }
  if (current == AT_START && distStart > startExitRadius) {
    return DEPARTED_START;
  }
  return EN_ROUTE;
}

void updateGeofencePhase(bool gpsValid, int satellites, double lat, double lng,
                        float& distStart, float& distFinish, TripPhase& phase) {
  distStart = -1.0f;
  distFinish = -1.0f;

  if (!gpsValid || satellites < kMinSatellitesForGeofence) {
    phase = gTripPhase;
    return;
  }

  distStart = distanceMeters(lat, lng, START_LAT, START_LNG);
  distFinish = distanceMeters(lat, lng, FINISH_LAT, FINISH_LNG);
  TripPhase proposed = computePhase(distStart, distFinish, gTripPhase);

  if (proposed == gTripPhase) {
    gCandidatePhase = proposed;
    gStablePhaseReads = 0;
  } else {
    if (proposed == gCandidatePhase) {
      if (gStablePhaseReads < 255) gStablePhaseReads++;
      if (gStablePhaseReads >= kStableReadsNeeded) {
        gTripPhase = proposed;
        gStablePhaseReads = 0;
      }
    } else {
      gCandidatePhase = proposed;
      gStablePhaseReads = 1;
    }
  }

  phase = gTripPhase;
}

// ── Peripherals ───────────────────────────────────────────────────────────────
HX711            frontScale, backScale;
TinyGPSPlus      gps;
WebSocketsServer webSocket(kWsPort);

SemaphoreHandle_t dataMutex;
TaskHandle_t      sensorTaskHandle, wsTaskHandle;

// ── Shared data ───────────────────────────────────────────────────────────────
struct SensorData {
  float  totalG     = 0.0f;
  bool   overload   = false;
  double latitude   = 0.0, longitude = 0.0;
  bool   gpsValid   = false;
  int    satellites = 0;
  float  distStartM = -1.0f;
  float  distFinishM = -1.0f;
  TripPhase tripPhase = AT_START;
  bool   frontReady = false, backReady = false;
} data;

bool wsConnected = false;

// ── Sensor task ───────────────────────────────────────────────────────────────
void sensorTask(void* /*pv*/) {
  float emaFront = 0.0f, emaBack = 0.0f;
  bool  initFront = false, initBack = false;

  while (true) {
    while (Serial2.available()) gps.encode(Serial2.read());

    bool fOk = frontScale.is_ready();
    bool bOk = backScale.is_ready();
    float rawFront = fOk ? frontScale.get_units(SAMPLES_PER_READ) : 0.0f;
    float rawBack  = bOk ? backScale.get_units(SAMPLES_PER_READ) : 0.0f;

    if (!initFront) { emaFront = rawFront; initFront = true; }
    else             emaFront = EMA_ALPHA * rawFront + (1.0f - EMA_ALPHA) * emaFront;

    if (!initBack)  { emaBack  = rawBack;  initBack  = true; }
    else             emaBack  = EMA_ALPHA * rawBack  + (1.0f - EMA_ALPHA) * emaBack;

    float total = max(0.0f, emaFront) + max(0.0f, emaBack);
    float prevTotal = data.totalG;
    if (abs(total - prevTotal) < DEADBAND_G) total = prevTotal;

    bool   valid = gps.location.isValid();
    double lat   = valid ? gps.location.lat() : data.latitude;
    double lng   = valid ? gps.location.lng() : data.longitude;
    int    sats  = gps.satellites.isValid() ? (int)gps.satellites.value() : 0;

    float distStartM = -1.0f;
    float distFinishM = -1.0f;
    TripPhase phase = gTripPhase;
    updateGeofencePhase(valid, sats, lat, lng, distStartM, distFinishM, phase);

    xSemaphoreTake(dataMutex, portMAX_DELAY);
    data.totalG     = total;
    data.overload   = (total >= MAX_WEIGHT_G);
    data.latitude   = lat;
    data.longitude  = lng;
    data.gpsValid   = valid;
    data.satellites = sats;
    data.distStartM = distStartM;
    data.distFinishM = distFinishM;
    data.tripPhase  = phase;
    data.frontReady = fOk;
    data.backReady  = bOk;
    xSemaphoreGive(dataMutex);

    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

// ── WS task ───────────────────────────────────────────────────────────────────
void wsTask(void* /*pv*/) {
  unsigned long lastSend = 0;
  unsigned long lastTare = 0;

  while (true) {
    webSocket.loop();

    unsigned long now = millis();

    // Periodic re-tare every 5 minutes to correct drift
    if (now - lastTare >= 300000UL) {
      lastTare = now;
      if (frontScale.is_ready()) frontScale.tare(10);
      if (backScale.is_ready())  backScale.tare(10);
    }

    if (now - lastSend >= kSendIntervalMs) {
      lastSend = now;

      SensorData snap;
      xSemaphoreTake(dataMutex, portMAX_DELAY);
      snap = data;
      xSemaphoreGive(dataMutex);

      String jsonPayload = "{";
      jsonPayload += "\"latitude\":" + String(snap.latitude, 6) + ",";
      jsonPayload += "\"longitude\":" + String(snap.longitude, 6) + ",";
      jsonPayload += "\"gps_valid\":" + String(snap.gpsValid ? "true" : "false") + ",";
      jsonPayload += "\"satellites\":" + String(snap.satellites) + ",";
      jsonPayload += "\"trip_phase\":\"" + String(phaseToString(snap.tripPhase)) + "\",";
      jsonPayload += "\"dist_to_start_m\":" + String(snap.distStartM, 2) + ",";
      jsonPayload += "\"dist_to_finish_m\":" + String(snap.distFinishM, 2) + ",";
      jsonPayload += "\"weight_g\":" + String(snap.totalG, 2) + ",";
      jsonPayload += "\"status\":\"" + String(snap.overload ? "OVERLOAD" : "NORMAL") + "\"";
      jsonPayload += "}";

      // Send to backend via HTTP POST only when station Wi-Fi is connected.
      if (WiFi.status() == WL_CONNECTED) {
        HTTPClient http;
        http.begin(kBackendUrl);
        http.addHeader("Content-Type", "application/json");

        int httpResponseCode = http.POST(jsonPayload);
        if (httpResponseCode > 0) {
          Serial.printf("HTTP POST success: %d\n", httpResponseCode);
        } else {
          Serial.printf("HTTP POST failed: %d\n", httpResponseCode);
        }
        http.end();
      } else {
        Serial.println("HTTP POST skipped: WiFi disconnected");
      }

      // Also broadcast to WebSocket for local clients
      String wsPayload = "{\"type\":\"telemetry\"";
      wsPayload += ",\"weight_g\":"    + String(snap.totalG,   2);
      wsPayload += ",\"status\":\""    + String(snap.overload ? "OVERLOAD" : "NORMAL") + "\"";
      wsPayload += ",\"satellites\":"  + String(snap.satellites);
      wsPayload += ",\"latitude\":"    + String(snap.latitude,  6);
      wsPayload += ",\"longitude\":"   + String(snap.longitude, 6);
      wsPayload += ",\"gps_valid\":"   + String(snap.gpsValid   ? "true" : "false");
      wsPayload += ",\"trip_phase\":\"" + String(phaseToString(snap.tripPhase)) + "\"";
      wsPayload += ",\"dist_to_start_m\":" + String(snap.distStartM, 2);
      wsPayload += ",\"dist_to_finish_m\":" + String(snap.distFinishM, 2);
      wsPayload += ",\"front_ready\":" + String(snap.frontReady ? "true" : "false");
      wsPayload += ",\"back_ready\":"  + String(snap.backReady  ? "true" : "false");
      wsPayload += "}";

      Serial.println(wsPayload);
      if (wsConnected) webSocket.broadcastTXT(wsPayload);
    }

    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

// ── WebSocket events ──────────────────────────────────────────────────────────
void onWsEvent(uint8_t clientNum, WStype_t type, uint8_t* payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      wsConnected = true;
      Serial.printf("WS client %u connected\n", clientNum);
      break;

    case WStype_DISCONNECTED:
      wsConnected = (webSocket.connectedClients() > 0);
      Serial.printf("WS client %u disconnected\n", clientNum);
      break;

    case WStype_TEXT: {
      if (length == 0) break;
      String msg = String((char*)payload);
      if (!msg.startsWith(kAuthToken)) {
        Serial.println("Auth failed");
        webSocket.disconnect(clientNum);
        break;
      }
      Serial.println("Auth OK");
      if (msg.indexOf("tare") != -1) {
        // No mutex here — avoids deadlock with periodic tare
        if (frontScale.is_ready()) frontScale.tare(10);
        if (backScale.is_ready())  backScale.tare(10);
        Serial.println("Scales tared");
      }
      break;
    }
    default: break;
  }
}

// ── Serial commands ───────────────────────────────────────────────────────────
float frontCal = FRONT_CAL, backCal = BACK_CAL;

void printStatus() {
  xSemaphoreTake(dataMutex, portMAX_DELAY);
  SensorData s = data;
  xSemaphoreGive(dataMutex);
  Serial.printf("Total: %.2f g  |  %s\n", s.totalG, s.overload ? "OVERLOAD" : "NORMAL");
  Serial.printf("GPS: %s  Sats: %d  Lat: %.6f  Lng: %.6f\n",
    s.gpsValid ? "valid" : "no fix", s.satellites, s.latitude, s.longitude);
  Serial.printf("Phase: %s  DistStart: %.2f m  DistFinish: %.2f m\n",
    phaseToString(s.tripPhase), s.distStartM, s.distFinishM);
}

void calibrateScale(HX711& scale, float& factor, const char* name, float knownG) {
  if (!scale.is_ready()) { Serial.printf("%s not ready\n", name); return; }
  scale.tare(10);
  Serial.printf("Place %.1f g on %s scale then press Enter...\n", knownG, name);
  while (!Serial.available()) delay(100);
  Serial.readStringUntil('\n');
  float reading = scale.get_units(20);
  if (reading <= 0.0f) { Serial.printf("Bad reading: %.2f\n", reading); return; }
  factor = factor * (reading / knownG);
  scale.set_scale(factor);
  Serial.printf("%s cal factor -> %.4f\n", name, factor);
}

void processSerial() {
  if (!Serial.available()) return;
  String line = Serial.readStringUntil('\n');
  line.trim();
  if (line.isEmpty()) return;

  if (line.equalsIgnoreCase("status")) { printStatus(); return; }

  if (line.equalsIgnoreCase("tare") || line.equalsIgnoreCase("tare all")) {
    if (frontScale.is_ready()) frontScale.tare(10);
    if (backScale.is_ready())  backScale.tare(10);
    Serial.println("Both scales tared");
    return;
  }
  if (line.startsWith("setcal front ")) {
    float f = line.substring(13).toFloat();
    if (f > 0) { frontCal = f; frontScale.set_scale(f); Serial.printf("Front cal -> %.4f\n", f); }
    return;
  }
  if (line.startsWith("setcal back ")) {
    float f = line.substring(12).toFloat();
    if (f > 0) { backCal = f; backScale.set_scale(f); Serial.printf("Back cal -> %.4f\n", f); }
    return;
  }
  if (line.startsWith("cal front ")) {
    calibrateScale(frontScale, frontCal, "Front", line.substring(10).toFloat());
    return;
  }
  if (line.startsWith("cal back ")) {
    calibrateScale(backScale, backCal, "Back", line.substring(9).toFloat());
    return;
  }
  Serial.println("Commands: status | tare | setcal front <n> | setcal back <n> | cal front <g> | cal back <g>");
}

void connectWiFi() {
  Serial.printf("Connecting to WiFi SSID '%s'...\n", kSsid);
  WiFi.begin(kSsid, kPassword);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 30000) {
    delay(500);
    Serial.print('.');
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\nWiFi connected, IP: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("\nWiFi connection failed");
  }
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(300);

  Serial2.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  Serial.println("GPS ready");

  frontScale.begin(FRONT_DT, FRONT_SCK);
  frontScale.set_scale(frontCal);
  backScale.begin(BACK_DT, BACK_SCK);
  backScale.set_scale(backCal);

  auto waitReady = [](HX711& s, const char* name) {
    unsigned long t = millis();
    while (!s.is_ready() && millis() - t < 5000) delay(10);
    Serial.printf("%s HX711: %s\n", name, s.is_ready() ? "OK" : "NOT READY");
  };
  waitReady(frontScale, "Front");
  waitReady(backScale,  "Back");

  Serial.println("Warming up scales (30s)...");
  delay(30000);
  frontScale.tare(30);
  backScale.tare(30);
  Serial.println("Tare done — baseline set");

  connectWiFi();  // Connect to phone hotspot
  webSocket.begin();
  webSocket.onEvent(onWsEvent);

  dataMutex = xSemaphoreCreateMutex();
  xTaskCreate(sensorTask, "Sensor", 4096, nullptr, 1, &sensorTaskHandle);
  xTaskCreate(wsTask,     "WS",     4096, nullptr, 2, &wsTaskHandle);

  Serial.println("Ready");
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {
  processSerial();
  vTaskDelay(pdMS_TO_TICKS(200));
}