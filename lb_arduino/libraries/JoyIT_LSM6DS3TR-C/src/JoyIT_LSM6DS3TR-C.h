#ifndef LSM6DS3TR_C_H
#define LSM6DS3TR_C_H

#include <Wire.h>
#include <Arduino.h>

// object to select linear acceleration sensitivity 
enum class AccelRange { G2,   // 0.061 mg/LSB
                        G4,   // 0.122 mg/LSB
                        G8,   // 0.244 mg/LSB
                        G16   // 0.488 mg/LSB
};

// object to select angular rate sensitivity
enum class GyroRange { DPS125,  // 4.375 mdps/LSB
                       DPS250,  // 8.75 mdps/LSB
                       DPS500,  // 17.50 mdps/LSB
                       DPS1000, // 35 mdps/LSB
                       DPS2000  // 70 mdps/LSB
};

// object to select output data range in Hz   
enum class ODR { Off = 0,
                 Hz12_5,
                 Hz26,
                 Hz52,
                 Hz104,
                 Hz208,
                 Hz416,
                 Hz833,
                 Hz1660,
                 Hz3330,
                 Hz6660 };

// object to safe read data from acceleration
struct Acceleration {
  float x, y, z;
};
// object to safe read data from gyroscope
struct Gyroscope {
  float x, y, z;
};

class LSM6DS3TR_C {
public:
  void begin(uint8_t address = 0x6B, AccelRange accel_sensitivity = AccelRange::G2, GyroRange gyro_sensitivity = GyroRange::DPS250, ODR data_rate = ODR::Hz104);
  void setAcceleration(AccelRange range);
  void setGyroscope(GyroRange range);
  void setOutputDataRange(ODR range);
  void getAcceleration(Acceleration &acc);
  void getGyroscope(Gyroscope &gyro);
  void getTemperature(float &temp);
  void readAll(Acceleration &acc, Gyroscope &gyro, float &temp);
  uint8_t whoAmI();
private:
  void writeRegister(uint8_t reg, uint8_t value);
  void readRegister(uint8_t reg, uint8_t *data, uint8_t length);
  void softReset();
  uint8_t getODRBits(ODR odr);
  uint8_t getAccelerationSensitivity(AccelRange accelsens);
  float getAccelerationSensitivityCalc(AccelRange accelsens);
  uint8_t getGyroscopeSensitivity(GyroRange gyrosens);
  float getGyroscopeSensitivityCalc(GyroRange gyrosens);
  int16_t calculateData(uint8_t data_low, uint8_t data_high);
  const uint8_t REG_FUNC_CFG_ACCESS = 0x01;
  const uint8_t REG_WHO_AM_I = 0x0F;
  const uint8_t REG_CTRL1_XL = 0x10;  // Accelerometer Control Register
  const uint8_t REG_CTRL2_G = 0x11;   // Gyroscope Control Register
  const uint8_t REG_CTRL3_C = 0x12;
  const uint8_t REG_OUT_TEMP_L = 0x20;
  const uint8_t REG_OUTX_L_G = 0x22;   // Gyroscope X-Axis Data (Low Byte)
  const uint8_t REG_OUTX_L_XL = 0x28;  // Accelerometer X-Axis Data (Low Byte)
  AccelRange accel_sensitivity;
  GyroRange gyro_sensitivity;
  ODR data_rate;
  uint8_t address;
  uint8_t _who;
};
#endif