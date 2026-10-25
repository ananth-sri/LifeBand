/*#define SDA_PIN 19
#define SCL_PIN 7

void setup() {
  Serial.begin(115200);

  pinMode(SDA_PIN, OUTPUT);
  pinMode(SCL_PIN, OUTPUT);

  digitalWrite(SDA_PIN, HIGH);
  digitalWrite(SCL_PIN, HIGH);

  Serial.println("SDA and SCL driven HIGH");
}

void loop() {
}
*/

#include <Wire.h>

#define SDA_PIN 19
#define SCL_PIN 7

void testAddress(uint8_t address)
{
  Serial.print("\nTesting address 0x");
  Serial.println(address, HEX);

  // Write register address
  Wire.beginTransmission(address);
  Wire.write(0x0F);       // WHO_AM_I
  uint8_t result = Wire.endTransmission(false);

  Serial.print("Write/register result = ");
  Serial.println(result);

  if (result != 0) {
    Serial.println("No ACK from this address.");
    return;
  }

  // Request WHO_AM_I
  uint8_t count = Wire.requestFrom(address, (uint8_t)1);

  Serial.print("Bytes received = ");
  Serial.println(count);

  if (count > 0) {
    uint8_t value = Wire.read();

    Serial.print("WHO_AM_I = 0x");
    Serial.println(value, HEX);
  } else {
    Serial.println("No data returned.");
  }
}

void setup()
{
  Serial.begin(115200);
  delay(1000);

  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);

  Serial.println("\nLSM6DS3TR-C I2C test");
  Serial.println("====================");

  testAddress(0x6A);
  testAddress(0x6B);
}

void loop()
{
}
