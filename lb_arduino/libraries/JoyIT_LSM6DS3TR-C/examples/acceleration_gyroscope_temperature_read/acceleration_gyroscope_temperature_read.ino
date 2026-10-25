
#include <Wire.h>
#include "JoyIT_LSM6DS3TR-C.h"

// object to read sensor data
LSM6DS3TR_C accelation_sensor;

void setup() {
  // setup serial communication
  Serial.begin(9600);
  // setup sensor
  accelation_sensor.begin();
}

// setup objects to read data
Acceleration acceleration;
Gyroscope gyroscope;
float temperature;

void loop() {
  // read all sensor data
  accelation_sensor.readAll(acceleration, gyroscope, temperature);
  // print acceleration data
  Serial.print(F("A[g]  x: ")); Serial.print(acceleration.x, 4);
  Serial.print(F("  y: "));     Serial.print(acceleration.y, 4);
  Serial.print(F("  z: "));     Serial.print(acceleration.z, 4);
  // print gyroscope data
  Serial.print(F(" | G[dps] x: ")); Serial.print(gyroscope.x, 2);
  Serial.print(F("  y: "));         Serial.print(gyroscope.y, 2);
  Serial.print(F("  z: "));         Serial.print(gyroscope.z, 2);
  // print temperature data
  Serial.print(F(" | T[°C]: ")); Serial.println(temperature, 2);
  // wait for 500 ms
  delay(500);
}
