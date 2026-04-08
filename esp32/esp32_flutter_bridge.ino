#include "BluetoothSerial.h"

BluetoothSerial SerialBT;

// Change this name to what you want to see when scanning from Flutter.
const char *kDeviceName = "SmartByahe-ESP32";

// Send telemetry every 1 second.
const unsigned long kSendIntervalMs = 1000;
unsigned long lastSendMs = 0;

String rxLine = "";
int passengerCount = 0;
bool countingEnabled = true;

void sendStatus() {
  // Send one-line JSON so Flutter can parse per newline.
  // Example:
  // {"type":"status","passenger_count":3,"counting_enabled":true}
  String payload = "{\"type\":\"status\",\"passenger_count\":";
  payload += passengerCount;
  payload += ",\"counting_enabled\":";
  payload += (countingEnabled ? "true" : "false");
  payload += "}";

  Serial.println(payload);
  if (SerialBT.hasClient()) {
    SerialBT.println(payload);
  }
}

void handleCommand(const String &line) {
  // Supported commands from Flutter:
  // set_count:5
  // inc
  // dec
  // reset
  // start
  // stop
  if (line.startsWith("set_count:")) {
    String value = line.substring(String("set_count:").length());
    passengerCount = value.toInt();
  } else if (line == "inc") {
    passengerCount++;
  } else if (line == "dec") {
    if (passengerCount > 0) passengerCount--;
  } else if (line == "reset") {
    passengerCount = 0;
  } else if (line == "start") {
    countingEnabled = true;
  } else if (line == "stop") {
    countingEnabled = false;
  }

  String ack = "{\"type\":\"ack\",\"command\":\"" + line + "\"}";
  Serial.println(ack);
  if (SerialBT.hasClient()) {
    SerialBT.println(ack);
  }
}

void readIncomingChar(char c) {
  if (c == '\r') return;

  if (c == '\n') {
    if (rxLine.length() > 0) {
      handleCommand(rxLine);
      rxLine = "";
    }
    return;
  }

  rxLine += c;
}

void setup() {
  Serial.begin(115200);
  SerialBT.begin(kDeviceName);  // Bluetooth Classic SPP

  Serial.println("ESP32 bridge started.");
  Serial.print("Bluetooth name: ");
  Serial.println(kDeviceName);
}

void loop() {
  // Receive from USB serial monitor.
  while (Serial.available()) {
    readIncomingChar((char)Serial.read());
  }

  // Receive from Flutter over Bluetooth.
  while (SerialBT.available()) {
    readIncomingChar((char)SerialBT.read());
  }

  // Replace this mock logic with your sensor/camera counting logic.
  // This example simply streams current state periodically.
  unsigned long now = millis();
  if (now - lastSendMs >= kSendIntervalMs) {
    lastSendMs = now;
    sendStatus();
  }
}
