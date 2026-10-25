
#include <Wire.h>

#define SDA_PIN 7
#define SCL_PIN 19


void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println();
  Serial.println("I2C Scanner");
  //pinMode(SDA_PIN, INPUT_PULLUP);
  //pinMode(SCL_PIN, INPUT_PULLUP);
  Wire.begin(SDA_PIN, SCL_PIN);
}

void loop() {
  byte error;
  int count = 0;

  Serial.println("Scanning...");

  for (byte address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    error = Wire.endTransmission();
   
    if (error == 0) {
      Serial.print("I2C device found at 0x");
      if (address < 16) Serial.print("0");
      Serial.println(address, HEX);
      count++;
    }
  }

  if (count == 0) {
    Serial.println("No I2C devices found.");
  } else {
    Serial.print("Found ");
    Serial.print(count);
    Serial.println(" device(s).");
  }

  Serial.println();
  delay(3000);
}


/*void setup() {
  Serial.begin(115200);

  pinMode(5, OUTPUT);
  
  digitalWrite(5, HIGH);
  delay(100);
  digitalWrite(5, LOW);
  delay(100);
}

void loop() {
  digitalWrite(5, HIGH);
  delay(100);
  digitalWrite(5, LOW);
  delay(100);
}
*/