// Program to monitor multiple sensors integrated into LifeBand
// Calculate distress score based on the algorithm
// If distress score is above threshold or manual distress SOS identified
// package up the payload on the edge
// ready to transmit to RX base station via LoRa
// standard libraries available for arduino
#include <Wire.h>
#include <SPI.h>
#include <LoRa.h>
#include <SparkFunLSM6DS3.h>
#include "MAX30105.h"
#include "heartRate.h"
#include <TinyGPS++.h>

// ==========================================
// PIN DEFINITIONS (ESP32-S3 Target)
// ==========================================
#define I2C_SDA_PIN      8
#define I2C_SCL_PIN      9

#define GPS_RX_PIN       17  // Connected to GT-U7 TX
#define GPS_TX_PIN       18  // Connected to GT-U7 RX
#define GPS_BAUD         9600

#define LORA_SCK_PIN     12
#define LORA_MISO_PIN    13
#define LORA_MOSI_PIN    11
#define LORA_CS_PIN      10
#define LORA_RST_PIN     14
#define LORA_DIO0_PIN    21
#define LORA_FREQ        915E6

#define MANUAL_SOS_PIN   4   // Tactile SOS Push Button (Active LOW)

// ==========================================
// PACKED BINARY TELEMETRY STRUCT (16 Bytes)
// Hold key information about device for 
// accurate identification
// ==========================================
struct __attribute__((__packed__)) LifeBandPayload {
    uint8_t  node_id;       // Device ID (e.g., 0x01)
    uint8_t  alert_flag;    // 0x00: Normal, 0x01: Auto Distress, 0x02: Manual SOS
    float    latitude;      // WGS84 Latitude
    float    longitude;     // WGS84 Longitude
    uint8_t  heart_rate;    // Calculated BPM
    uint8_t  spo2;          // SpO2 Percentage
    uint16_t battery_mv;    // Battery Voltage in mV
};

// ==========================================
// GLOBAL OBJECTS & STATE MANAGEMENT
// ==========================================
MAX30105 particleSensor;
LSM6DS3 imu(I2C_MODE, 0x6B);
TinyGPSPlus gps;
HardwareSerial gpsSerial(1); // Use UART1

volatile bool manualSosTriggered = false;
unsigned long lastSensorReadTime = 0;
const unsigned long SENSOR_INTERVAL_MS = 20; // 50 Hz loop execution

// BPM: Heart Rate Variables
const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatsPerMinute = 0.0;
int beatAvg = 0;

// Manual SOS: Interrupt Service Routine
void IRAM_ATTR handleSosInterrupt() {
    manualSosTriggered = true;
}

// Initialization of all sensors/components
void setup() {
    Serial.begin(115200);
    pinMode(MANUAL_SOS_PIN, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(MANUAL_SOS_PIN), handleSosInterrupt, FALLING);

    // 1. Initialize I2C Bus & Sensors
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    
    if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
        Serial.println(F("[ERROR] MAX30102 PPG sensor not detected!"));
    } else {
        particleSensor.setup(); 
        particleSensor.setPulseAmplitudeRed(0x0A);
        particleSensor.setPulseAmplitudeGreen(0);
    }

    if (imu.begin() != 0) {
        Serial.println(F("[ERROR] LSM6DS3 IMU initialization failed!"));
    }

    // 2. Initialize GPS Serial
    gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);

    // 3. Initialize SPI & SX1276 LoRa
    SPI.begin(LORA_SCK_PIN, LORA_MISO_PIN, LORA_MOSI_PIN, LORA_CS_PIN);
    LoRa.setPins(LORA_CS_PIN, LORA_RST_PIN, LORA_DIO0_PIN);
    
    if (!LoRa.begin(LORA_FREQ)) {
        Serial.println(F("[ERROR] SX1276 LoRa transceiver initialization failed!"));
        while (1);
    }
    
    LoRa.setSpreadingFactor(7);
    LoRa.setSignalBandwidth(125E3);
    LoRa.setCodingRate4(5);
    LoRa.sleep(); // Default to low-power sleep state

    Serial.println(F("[SUCCESS] LifeBand Edge Initialization Complete. Starting Loop..."));
}

// Distress identification: Ingest and process incoming data from all sensors
void loop() {
    // A. Continually Ingest Incoming NMEA GPS Streams
    while (gpsSerial.available() > 0) {
        gps.encode(gpsSerial.read());
    }

    // B. Non-blocking High-Frequency Sensor Polling (50 Hz)
    if (millis() - lastSensorReadTime >= SENSOR_INTERVAL_MS) {
        lastSensorReadTime = millis();
        
        // 1. Sample PPG Optical Sensor
        long irValue = particleSensor.getIR();
        if (checkForBeat(irValue) == true) {
            long delta = millis() - lastBeat;
            lastBeat = millis();
            beatsPerMinute = 60 / (delta / 1000.0);

            if (beatsPerMinute < 255 && beatsPerMinute > 20) {
                rates[rateSpot++] = (byte)beatsPerMinute;
                rateSpot %= RATE_SIZE;
                beatAvg = 0;
                for (byte x = 0; x < RATE_SIZE; x++) {
                    beatAvg += rates[x];
                }
                beatAvg /= RATE_SIZE;
            }
        }

        // 2. Sample 6-Axis IMU Acceleration Vector
        float ax = imu.readFloatAccelX();
        float ay = imu.readFloatAccelY();
        float az = imu.readFloatAccelZ();
        float accelMagnitude = sqrt(ax * ax + ay * ay + az * az);

        // 3. Edge Distress Decision Logic f(t)
        uint8_t alertState = 0x00; // 0x00 = Normal

        if (manualSosTriggered) {
            alertState = 0x02; // Manual SOS Override
            manualSosTriggered = false; // Reset flag
        } else if (accelMagnitude < 0.25 && (beatAvg > 150 || beatAvg < 40) && beatAvg != 0) {
            // Condition: Inactivity/Freefall combined with extreme cardiac anomaly
            alertState = 0x01; // Automated Edge Distress
        }

        // 4. Construct Payload & Broadcast Over Sub-GHz RF if Flagged
        if (alertState > 0x00) {
            dispatchEmergencyPayload(alertState, beatAvg);
        }
    }
}

// ==========================================
// LORA PACKET DISPATCH ROUTINE
// ==========================================
void dispatchEmergencyPayload(uint8_t alertFlag, int currentBpm) {
    LifeBandPayload payload;
    payload.node_id = 0x01;
    payload.alert_flag = alertFlag;
    payload.latitude = gps.location.isValid() ? (float)gps.location.lat() : 0.0f;
    payload.longitude = gps.location.isValid() ? (float)gps.location.lng() : 0.0f;
    payload.heart_rate = (uint8_t)currentBpm;
    payload.spo2 = 98; // Simulated value; integrate MAX30102 Red/IR ratio algorithm as needed
    payload.battery_mv = 3700; // Replace with analogRead(BATTERY_ADC_PIN) calculation

    // Transmit Packed Struct via LoRa
    // wakeup
    LoRa.idle();
    // ready LoRa to start transmission
    LoRa.beginPacket();
    // create a tight memory payload
    LoRa.write((uint8_t*)&payload, sizeof(payload));
    // close the payload
    LoRa.endPacket();
    // end and sleep mode to conserve power
    LoRa.sleep(); // Return radio to low-power sleep mode

    // Verification Output
    Serial.print(F("[ALERT DISPATCHED] Flag: "));
    Serial.print(payload.alert_flag);
    Serial.print(F(" | Lat: "));
    Serial.print(payload.latitude, 6);
    Serial.print(F(" | Lng: "));
    Serial.print(payload.longitude, 6);
    Serial.print(F(" | BPM: "));
    Serial.println(payload.heart_rate);
}
// Sample payload at TX end
// Field,Size,Data Type,Sample Hex Bytes,Decoded Value
// node_id,1 Byte,uint8_t,0x01,Device ID #1
// alert_flag,1 Byte,uint8_t,0x02,2 (Manual SOS Trigger)
// latitude,4 Bytes,float,0x41 0xF2 0x23 0x3A,30.2672° N
// longitude,4 Bytes,float,0xC2 0xC3 0x7C 0x88,-97.7431° W
// heart_rate,1 Byte,uint8_t,0x4E,78 BPM
// spo2,1 Byte,uint8_t,0x62,98%
// battery_mv,2 Bytes,uint16_t,0x0E 0x74,3700 mV (3.7V)

// and then this needs to be converted to a json payload at RX end
// unpacked sample payload
//{
//  "node_id": 1,
//  "alert_flag": 2,
//  "status": "MANUAL_SOS",
//  "location": {
//    "latitude": 30.267200,
//    "longitude": -97.743100
//  },
//  "vitals": {
//    "heart_rate_bpm": 78,
//    "spo2_percent": 98
//  },
//  "telemetry": {
//    "battery_mv": 3700,
//    "rssi_dbm": -74
//  }
//}
