#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000 // 915 MHz freq
#define TX_POWER 14            // Output power in dBm
#define TOTAL_PACKETS 100      // Packet count
#define TX_INTERVAL_MS 1000    // Delay between packets (ms)

// Program:
// send LBSEQ:<count> packet with a constant delay
// at the receiver end, check what packets are received
// calculate PLR at rx end to determine Packet Loss Rate (%)
// test run with 100 packets

static RadioEvents_t RadioEvents;
char txpacket[50];
uint16_t packetCounter = 1;
bool txDone = true;

void OnTxDone(void) {
  Serial.print("Sent Packet #");
  Serial.println(packetCounter - 1);
  txDone = true;
}

void OnTxTimeout(void) {
  Serial.println("Tx Timeout");
  txDone = true;
}

void setup() {
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.TxDone = OnTxDone;
  RadioEvents.TxTimeout = OnTxTimeout;

  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);

// use standard practices to set these
  Radio.SetTxConfig(
    MODEM_LORA,
    TX_POWER,
    0,           // Frequency deviation (FSK only)
    0,           // Bandwidth: 0 [125 kHz]
    7,           // Spreading Factor: SF7 standard
    1,           // Coding Rate: 1 [4/5]
    8,           // Preamble length
    false,       // Fixed length payload
    true,        // CRC enable
    0,           // Frequency hopping
    0,           // Hop period
    false,       // Invert IQ
    3000         // Timeout (ms)
  );


  Serial.println("Starting Packet Loss Test Transmission...");
}

void loop() {
  Radio.IrqProcess();

// loop through sending 0-100 packets giving a delay 
// between transmission
  if (txDone && packetCounter <= TOTAL_PACKETS) {
    txDone = false;
    
    // Format payload with packet number so we get LBSEQ:# at rx end
    snprintf(txpacket, sizeof(txpacket), "LBSEQ:%d", packetCounter);
    
    Serial.print("Transmitting: ");
    Serial.println(txpacket);

    Radio.Send((uint8_t *)txpacket, strlen(txpacket));
    packetCounter++;

    delay(TX_INTERVAL_MS);
  } else if (packetCounter > TOTAL_PACKETS && txDone) {
    Serial.println("Completed sending 100 packets. Reset board to restart test.");
    while (1) {
      delay(1000); // Stop transmitting after 100 packets
    }
  }
}