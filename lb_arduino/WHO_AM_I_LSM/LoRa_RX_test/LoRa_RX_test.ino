#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000

char rxpacket[50];

static RadioEvents_t RadioEvents;


void OnRxDone(
  uint8_t *payload,
  uint16_t size,
  int16_t rssi,
  int8_t snr
)
{
  memcpy(rxpacket, payload, size);
  rxpacket[size] = '\0';

  Serial.println("Received:");
  Serial.println(rxpacket);

  Serial.print("RSSI: ");
  Serial.println(rssi);

  Radio.Rx(0);
}


void setup()
{
  Serial.begin(115200);

  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.RxDone = OnRxDone;

  Radio.Init(&RadioEvents);

  Radio.SetChannel(RF_FREQUENCY);

  Radio.SetRxConfig(
    MODEM_LORA,
    0,
    7,
    1,
    0,
    8,
    0,
    false,
    0,
    true,
    0,
    0,
    false,
    true
  );

  Serial.println("LoRa Receiver Ready");

  Radio.Rx(0);
}


void loop()
{
  Radio.IrqProcess();
}