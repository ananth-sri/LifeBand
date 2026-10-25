// SF testing
// Spreading Factor Spreading Factor is the number of chirps to encode a symbol of digital data
// it is a trade-off dial between range/reliability and speed/battery life.
// lower SF == faster but less reliable reception
// higher SF == slower but more reliable reception
// SF7: $2^7 = 128$ chirps per symbol
// SF8: $2^8 = 256$ chirps per symbol

// Program: 
// transmit 10 packets at each SF7 through SF12 and check packets sequentially.
// payload includes active SF
// RX adjusts on the fly and reports Packet Loss Rate (PLR), RSSI, and SNR for each SF.

#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000 // 915 MHz 
#define TX_POWER 14            // dBm
#define PACKETS_PER_SF 10
#define TX_INTERVAL_MS 1000

static RadioEvents_t RadioEvents;
char txpacket[50];

uint8_t currentSF = 7;
uint16_t packetCounter = 1;
bool txDone = true;

// configure to a specific spreading factor
void configureRadioSF(uint8_t sf) {
  Radio.SetTxConfig(
    MODEM_LORA,
    TX_POWER,
    0,           // FSK freq dev
    0,           // BW: 0 [125 kHz]
    sf,          // Spreading Factor (7-12)
    1,           // Coding Rate: 1 [4/5]
    8,           // Preamble length
    false,       // Fixed length payload
    true,        // CRC enable
    0, 0, false, 3000
  );
  Serial.printf("\n--- Radio Configured to SF%d ---\n", sf);
}

void OnTxDone(void) {
  txDone = true;
}

void OnTxTimeout(void) {
  Serial.println("TX Timeout");
  txDone = true;
}

void setup() {
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.TxDone = OnTxDone;
  RadioEvents.TxTimeout = OnTxTimeout;

  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);
  
  configureRadioSF(currentSF);
  Serial.println("Starting Spreading Factor Test...");
}
// send 10 packets at each SF, wait and then move to next
void loop() {
  Radio.IrqProcess();

  if (txDone) {
    if (packetCounter > PACKETS_PER_SF) {
      // Move to next Spreading Factor
      packetCounter = 1;
      currentSF++;
      
      if (currentSF > 12) {
        currentSF = 7; // Loop back to SF7 or stop
        Serial.println("\n=== Completed full SF7-SF12 Sweep. Restarting... ===");
      }
      
      configureRadioSF(currentSF);
      delay(2000); // Wait between SF config changes
    }

    txDone = false;
    
    // Payload format: "SF:7,LBSEQ:1"
    snprintf(txpacket, sizeof(txpacket), "SF:%d,LBSEQ:%d", currentSF, packetCounter);
    
    Serial.printf("Transmitting on SF%d -> Packet %d/%d\n", currentSF, packetCounter, PACKETS_PER_SF);
    Radio.Send((uint8_t *)txpacket, strlen(txpacket));
    
    packetCounter++;
    delay(TX_INTERVAL_MS);
  }
}
