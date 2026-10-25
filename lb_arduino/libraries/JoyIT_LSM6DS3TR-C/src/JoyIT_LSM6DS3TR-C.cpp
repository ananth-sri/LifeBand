#include <Wire.h>
#include "JoyIT_LSM6DS3TR-C.h"


// ++++++++++++++++++++++++++++++ public ++++++++++++++++++++++++++++++
void LSM6DS3TR_C::begin(uint8_t address, AccelRange accel_sensitivity,
                        GyroRange gyro_sensitivity, ODR data_rate) {

  // Start I2C using Heltec V3 pins
  Wire.setClock(400000);

  // Set device address BEFORE communicating with the sensor
  (*this).address = address;

  // Reset device
  (*this).softReset();

  // Set output data rate
  (*this).data_rate = data_rate;

  // Set accelerometer sensitivity
  (*this).accel_sensitivity = accel_sensitivity;
  (*this).setAcceleration((*this).accel_sensitivity);

  // Set gyroscope sensitivity
  (*this).gyro_sensitivity = gyro_sensitivity;
  (*this).setGyroscope((*this).gyro_sensitivity);

  // Read device ID
  uint8_t id = 0;
  (*this).readRegister((*this).REG_WHO_AM_I, &id, 1);
  (*this)._who = id;
}

// method to see device ID
uint8_t LSM6DS3TR_C::whoAmI() {
  return (*this)._who;
}

// method to set linear acceleration sensitivity
void LSM6DS3TR_C::setAcceleration(AccelRange range) {
  (*this).writeRegister((*this).REG_CTRL1_XL, (*this).getODRBits((*this).data_rate) | (*this).getAccelerationSensitivity(range));
  (*this).accel_sensitivity = range;
}

// method to set angular rate sensitivity 
void LSM6DS3TR_C::setGyroscope(GyroRange range) {
  (*this).writeRegister((*this).REG_CTRL2_G, (*this).getODRBits((*this).data_rate) | (*this).getGyroscopeSensitivity(range));
  (*this).gyro_sensitivity = range;
}

// method to set output data range
void LSM6DS3TR_C::setOutputDataRange(ODR range){
  (*this).data_rate = range;
  (*this).setGyroscope((*this).gyro_sensitivity);
  (*this).setAcceleration((*this).accel_sensitivity);
}

// read acceleration data
void LSM6DS3TR_C::getAcceleration(Acceleration &acc) {
  uint8_t data[6];
  // Read accelerometer data
  (*this).readRegister((*this).REG_OUTX_L_XL, data, 6);
  // put read data into acceleration object
  acc.x = (*this).calculateData(data[0], data[1]) * (*this).getAccelerationSensitivityCalc((*this).accel_sensitivity);
  acc.y = (*this).calculateData(data[2], data[3]) * (*this).getAccelerationSensitivityCalc((*this).accel_sensitivity);
  acc.z = (*this).calculateData(data[4], data[5]) * (*this).getAccelerationSensitivityCalc((*this).accel_sensitivity);
}

// read gyroscope data
void LSM6DS3TR_C::getGyroscope(Gyroscope &gyro) {
  uint8_t data[6];
  // Read accelerometer data
  (*this).readRegister((*this).REG_OUTX_L_G, data, 6);
  // put read data into gyroscope object
  gyro.x = (*this).calculateData(data[0], data[1]) * (*this).getGyroscopeSensitivityCalc((*this).gyro_sensitivity);
  gyro.y = (*this).calculateData(data[2], data[3]) * (*this).getGyroscopeSensitivityCalc((*this).gyro_sensitivity);
  gyro.z = (*this).calculateData(data[4], data[5]) * (*this).getGyroscopeSensitivityCalc((*this).gyro_sensitivity);
}

// read temperature data
void LSM6DS3TR_C::getTemperature(float &temp) {
  uint8_t data[2];
  (*this).readRegister((*this).REG_OUT_TEMP_L, data, 2);
  temp = 25.0f + ((*this).calculateData(data[0], data[1]) / 256.0f);
}

// read all data
void LSM6DS3TR_C::readAll(Acceleration &acc, Gyroscope &gyro, float &temp) {
  (*this).getAcceleration(acc);
  (*this).getGyroscope(gyro);
  (*this).getTemperature(temp);
}

// ++++++++++++++++++++++++++++++ private ++++++++++++++++++++++++++++++

// method to write into registers
void LSM6DS3TR_C::writeRegister(uint8_t reg, uint8_t value) {
  Wire.beginTransmission((*this).address);
  Wire.write(reg);
  Wire.write(value);
  Wire.endTransmission();
}

// method to read from registers
void LSM6DS3TR_C::readRegister(uint8_t reg, uint8_t *data, uint8_t length) {
  Wire.beginTransmission((*this).address);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom((*this).address, length);
  for (int i = 0; i < length; i++) {
    data[i] = Wire.read();
  }
}

// method to reset device
void LSM6DS3TR_C::softReset() {
  // software reset
  (*this).writeRegister((*this).REG_CTRL3_C, 0x01);
  delay(10);
  // otput registers are not updated until MSB and LSB have been read & setup SPI connection
  (*this).writeRegister((*this).REG_CTRL3_C, 0x44);
}

//  ++++++++++++++++++++++++++++++ Help methods ++++++++++++++++++++++++++++++

// transform ODR selection into repective HEX value
uint8_t LSM6DS3TR_C::getODRBits(ODR odr) {
  switch (odr) {
    case ODR::Off: return 0x00;
    case ODR::Hz12_5: return 0x10;
    case ODR::Hz26: return 0x20;
    case ODR::Hz52: return 0x30;
    case ODR::Hz104: return 0x40;
    case ODR::Hz208: return 0x50;
    case ODR::Hz416: return 0x60;
    case ODR::Hz833: return 0x70;
    case ODR::Hz1660: return 0x80;
    case ODR::Hz3330: return 0x90;
    case ODR::Hz6660: return 0xA0;
    default: return 0x40;  // 104 Hz
  }
}

// transform selection of linear acceleration sensitivity into repective HEX value
uint8_t LSM6DS3TR_C::getAccelerationSensitivity(AccelRange accelsens) {
  switch (accelsens) {
    case AccelRange::G2: return 0x00;
    case AccelRange::G4: return 0x04;
    case AccelRange::G8: return 0x08;
    case AccelRange::G16: return 0x0C;
  }
}

// transform selection of linear acceleration sensitivity into repective decimal value for calculation
float LSM6DS3TR_C::getAccelerationSensitivityCalc(AccelRange accelsens) {
  switch (accelsens) {
    case AccelRange::G2: return 0.000061f;
    case AccelRange::G4: return 0.000122f;
    case AccelRange::G8: return 0.000244f;
    case AccelRange::G16: return 0.000488f;
  }
}

// transform selection of angular rate sensitivity into repective HEX value
uint8_t LSM6DS3TR_C::getGyroscopeSensitivity(GyroRange gyrosens) {
  switch (gyrosens) {
    case GyroRange::DPS125: return 0x02;
    case GyroRange::DPS250: return 0x00;
    case GyroRange::DPS500: return 0x04;
    case GyroRange::DPS1000: return 0x08;
    case GyroRange::DPS2000: return 0x0C;
  }
}

// transform selection of angular rate sensitivity into repective decimal value for calculation
float LSM6DS3TR_C::getGyroscopeSensitivityCalc(GyroRange gyrosens) {
  switch (gyrosens) {
    case GyroRange::DPS125: return 0.004375f;
    case GyroRange::DPS250: return 0.00875f;
    case GyroRange::DPS500: return 0.01750f;
    case GyroRange::DPS1000: return 0.03500f;
    case GyroRange::DPS2000: return 0.07000f;
  }
}

// method for calculation
int16_t LSM6DS3TR_C::calculateData(uint8_t data_low, uint8_t data_high) {
  return (int16_t) data_low | (data_high << 8);
}
