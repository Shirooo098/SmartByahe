#include "HX711.h"
#include <TinyGPS++.h>

// HX711 pins
#define FRONT_DT  4
#define FRONT_SCK 5
#define BACK_DT   18
#define BACK_SCK  19

// Calibration
#define FRONT_CAL  433.57
#define BACK_CAL   434.68
#define MAX_WEIGHT 4000

TinyGPSPlus gps;

double latitude  = 0.0;
double longitude = 0.0;

HX711 frontScale;
HX711 backScale;

void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, 16, 17);

  frontScale.begin(FRONT_DT, FRONT_SCK);
  frontScale.set_scale(FRONT_CAL);
  frontScale.tare();

  backScale.begin(BACK_DT, BACK_SCK);
  backScale.set_scale(BACK_CAL);
  backScale.tare();

  Serial.println("=== Bus Weight Monitor ===");
  Serial.println("Max limit: 4kg");
  Serial.println("Ready!");
}

void loop() {
  // Read GPS
  while (Serial2.available()) {
    if (gps.encode(Serial2.read())) {
      if (gps.location.isValid()) {
        latitude  = gps.location.lat();
        longitude = gps.location.lng();
      }
    }
  }

  // GPS timeout warning
  if (millis() > 10000 && gps.charsProcessed() < 10) {
    Serial.println("GPS ERROR: No data received. Check wiring!");
  }

  if (frontScale.is_ready() && backScale.is_ready()) {
    float frontWeight = max(0.0f, frontScale.get_units(10));
    float backWeight  = max(0.0f, backScale.get_units(10));

    // Filter noise BEFORE summing
    if (frontWeight < 50) frontWeight = 0;
    if (backWeight  < 50) backWeight  = 0;

    float totalWeight = frontWeight + backWeight;

    float frontPct = 0, backPct = 0;
    if (totalWeight > 0) {
      frontPct = (frontWeight / totalWeight) * 100;
      backPct  = (backWeight  / totalWeight) * 100;
    }

    String status = (totalWeight >= MAX_WEIGHT) ? "OVERLOAD" : "NORMAL";

    // Human readable
    Serial.println("==========================");
    Serial.print("Front  : "); Serial.print(frontWeight, 1); Serial.println(" g");
    Serial.print("Back   : "); Serial.print(backWeight, 1);  Serial.println(" g");
    Serial.print("Total  : "); Serial.print(totalWeight, 1); Serial.println(" g");
    Serial.print("Front% : "); Serial.print(frontPct, 1);    Serial.println(" %");
    Serial.print("Back%  : "); Serial.print(backPct, 1);     Serial.println(" %");
    Serial.print("Status : "); Serial.println(status);

    if (gps.location.isValid()) {
      Serial.print("Lat    : "); Serial.println(latitude, 6);
      Serial.print("Lng    : "); Serial.println(longitude, 6);
    } else {
      Serial.println("GPS    : Waiting for fix...");
    }

    // CSV
    Serial.print("DATA,");
    Serial.print(frontWeight);  Serial.print(",");
    Serial.print(backWeight);   Serial.print(",");
    Serial.print(totalWeight);  Serial.print(",");
    Serial.print(frontPct);     Serial.print(",");
    Serial.print(backPct);      Serial.print(",");
    Serial.print(status);       Serial.print(",");
    Serial.print(latitude, 6);  Serial.print(",");
    Serial.println(longitude, 6);

  } else {
    Serial.println("Waiting for load cells...");
  }

  delay(2000);
}
