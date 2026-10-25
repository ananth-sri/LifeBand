# JoyIT_LSM6DS3TR-C
Library to read data from LSM6DS3TR-C with an Arduino


## Objects to read data
### Acceleration
```C++
// object to safe read data from acceleration
struct Acceleration {
  float x, y, z;
};
```
The purpose of this object is to save the read data from x-, y- and z-axis when reading acceleration.
### Gyroscope
```C++
// object to safe read data from gyroscope
struct Gyroscope {
  float x, y, z;
};
```
The purpose of this object is to save the read data from x-, y- and z-axis when reading gyroscope.
## Objects to adjust resolution
The following objects are used to adjust the resolution of the sensor.
### Acceleration
| AccelRange  | Resolution |
| ------------- | ------------- |
|  ± 2 g | 0.061 mg/LSB |
|  ± 4 g  | 0.122 mg/LSB |
|  ± 8 g  | 0.244 mg/LSB |
|  ± 16 g  | 0.488 mg/LSB  |
```C++
// object to select linear acceleration sensitivity 
enum class AccelRange { G2,   // 0.061 mg/LSB
                        G4,   // 0.122 mg/LSB
                        G8,   // 0.244 mg/LSB
                        G16   // 0.488 mg/LSB
};
```
### Gyroscope
| GyroRange (degrees per second)  | Resolution |
| ------------- | ------------- |
|  ± 125 dps | 4.375 mdps/LSB  |
|  ± 250 dps  | 8.75 mdps/LSB  |
|  ± 500 dps  | 17.50 mdps/LSB |
|  ± 1000 dps  | 35 mdps/LSB  |
|  ± 2000 dps  | 70 mdps/LSB  |
```C++
// object to select angular rate sensitivity
enum class GyroRange { DPS125,  // 4.375 mdps/LSB
                       DPS250,  // 8.75 mdps/LSB
                       DPS500,  // 17.50 mdps/LSB
                       DPS1000, // 35 mdps/LSB
                       DPS2000  // 70 mdps/LSB
};
```

### Output data range
| ODR  | Resolution |
| ------------- | ------------- |
| `Off`  | 0 Hz |
| `Hz12_5` | 12.5 Hz |
| `Hz26` | 26 Hz |
| `Hz52` | 52 Hz |
| `Hz104` | 104 Hz |
| `Hz208` | 208 Hz |
| `Hz416` | 416 Hz |
| `Hz833` | 833 Hz |
| `Hz1660` | 1660 Hz |
| `Hz3330` | 3330 Hz |
| `Hz6660` | 6660 Hz |
```C++
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
```
## Methods

```C++
begin(uint8_t address = 0x6B, AccelRange accel_sensitivity = AccelRange::G2, GyroRange gyro_sensitivity = GyroRange::DPS250, ODR data_rate = ODR::Hz104)
```
The method `begin` has to be executed before any other method can be executed. In this method everything is set up so the sensor can be read. The default values can be adjusted.

----

```C++
whoAmI()
```
The method `whoAmI` returns value from the `WHO_AM_I` register. It should be 0x6A.

----

```C++
setAcceleration(AccelRange range)
```
With the method `setAcceleration` you can select / reselect the resolution for the acceleration. 

----

```C++
setGyroscope(GyroRange range)
```
With the method `setGyroscope` you can select / reselect the resolution for the gyroscope. 

----

```C++
setOutputDataRange(ODR range)
```
With the method `setOutputDataRange` you can select / reselect the resolution for output data range. This method also adjusts gyroscope and acceleration to the newly selected output data range. 

----

```C++
getAcceleration(Acceleration &acc)
```
The method `getAcceleration` receives a reference of an `Acceleration` object and fills it with read data.

----

```C++
getGyroscope(Gyroscope &gyro)
```
The method `getGyroscope` receives a reference of a `Gyroscope` object and fills it with read data.

----

```C++
getTemperature(float &temp)
```
The method `getTemperature` receives a reference of a `float` object and fills it with read data.

----

```C++
readAll(Acceleration &acc, Gyroscope &gyro, float &temp)
```
The method `readAll`receives references of an `Acceleratio`n object, `Gyroscope` object and `float` object. It executes `getAcceleration`, `getGyroscope` and `getTemperature` and fills the data into the given references.
