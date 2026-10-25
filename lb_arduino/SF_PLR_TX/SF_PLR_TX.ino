// SF testing - TX (handshake mode, matching RX)
#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000
#define TX_POWER 14
#define PACKETS_PER_SF 10
#define CONTROL_SF 7
#define ACK_TIMEOUT_MS 3000

static RadioEvents_t RadioEvents;
char txpacket[30];
char rxpacket[30];

enum TxState { SEND_SYNC, WAIT_ACK, TRANSMITTING_DATA, INTER_SF_DELAY };
TxState state = SEND_SYNC;

uint8_t currentSF = 7; // Sweep from SF7 to SF12
uint8_t currentSeq = 1;

volatile bool txDone = true;
volatile bool rxDone = false;
volatile bool rxTimeout = false;

uint32_t syncStartTime = 0;
uint32_t stateTimer = 0;

void configureTxSF(uint8_t sf) {
  Radio.SetTxConfig(MODEM_LORA, TX_POWER, 0, 0, sf, 1, 8, false, true, 0, 0, false, 3000);
}

void configureRxSF(uint8_t sf) {
  Radio.SetRxConfig(MODEM_LORA, 0, sf, 1, 0, 8, 0, false, 0, true, 0, 0, false, true);
}

void OnTxDone(void) { txDone = true; }
void OnTxTimeout(void) { txDone = true; }

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  memcpy(rxpacket, payload, size);
  rxpacket[size] = '\0';
  rxDone = true;
}

void OnRxTimeout(void) { rxTimeout = true; }
void OnRxError(void) { rxTimeout = true; }

void setup() {
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.TxDone = OnTxDone;
  RadioEvents.TxTimeout = OnTxTimeout;
  RadioEvents.RxDone = OnRxDone;
  RadioEvents.RxTimeout = OnRxTimeout;
  RadioEvents.RxError = OnRxError;
  
  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);

  Serial.println("=== LoRa TX Sweep Initialized (Handshake Mode) ===");
  Serial.printf("Targeting SF7 through SF12 | %d packets per SF\n\n", PACKETS_PER_SF);
}

void loop() {
  Radio.IrqProcess();

  switch (state) {
    
    case SEND_SYNC: {
      Serial.printf("\n--- Starting Test Cycle for SF%d ---\n", currentSF);
      snprintf(txpacket, sizeof(txpacket), "SYNC:%d", currentSF);
      
      configureTxSF(CONTROL_SF);
      txDone = false;
      Serial.printf("[TX] Sending SYNC for SF%d on Control Channel (SF%d)...\n", currentSF, CONTROL_SF);
      Radio.Send((uint8_t *)txpacket, strlen(txpacket));
      
      while (!txDone) Radio.IrqProcess();
      
      // Immediately switch to Control SF RX mode to listen for ACK
      configureRxSF(CONTROL_SF);
      rxDone = false;
      rxTimeout = false;
      Radio.Rx(ACK_TIMEOUT_MS);
      
      syncStartTime = millis();
      state = WAIT_ACK;
      break;
    }

    case WAIT_ACK: {
      if (rxDone) {
        rxDone = false;
        int ackSF = 0;
        if (sscanf(rxpacket, "ACK:%d", &ackSF) == 1 && ackSF == currentSF) {
          Serial.printf("[ACK RECEIVED] Handshake successful for SF%d. Switching to data mode...\n", currentSF);
          currentSeq = 1;
          state = TRANSMITTING_DATA;
          delay(100); // Brief buffer for RX state transition
        } else {
          Serial.println("[ACK MISMATCH] Received invalid ACK frame, retrying SYNC...");
          state = SEND_SYNC;
        }
      } 
      else if (rxTimeout || (millis() - syncStartTime > ACK_TIMEOUT_MS)) {
        Serial.println("[ACK TIMEOUT] No response from RX. Retrying SYNC...");
        delay(1000); // Backoff before retrying handshake
        state = SEND_SYNC;
      }
      break;
    }

    case TRANSMITTING_DATA: {
      snprintf(txpacket, sizeof(txpacket), "SF:%d,LBSEQ:%d", currentSF, currentSeq);
      
      configureTxSF(currentSF);
      txDone = false;
      Serial.printf("[TX DATA] SF%d | Packet %d/%d\n", currentSF, currentSeq, PACKETS_PER_SF);
      Radio.Send((uint8_t *)txpacket, strlen(txpacket));
      
      while (!txDone) Radio.IrqProcess();

      // Inter-packet delay scales with Spreading Factor due to Time-on-Air (ToA)
      uint32_t packetDelay = (currentSF >= 10) ? 1200 : 500;
      delay(packetDelay);

      if (currentSeq >= PACKETS_PER_SF) {
        Serial.printf("=== Completed SF%d Transmission Cycle ===\n", currentSF);
        currentSF++;
        if (currentSF > 12) {
          Serial.println("\n🎉 === ALL SF SWEEP TESTS COMPLETED (SF7-SF12) ===");
          Serial.println("Restarting full sweep in 10 seconds...");
          currentSF = 7;
          stateTimer = millis();
          state = INTER_SF_DELAY;
        } else {
          stateTimer = millis();
          state = INTER_SF_DELAY;
        }
      } else {
        currentSeq++;
      }
      break;
    }

    case INTER_SF_DELAY: {
      // 3-second cooldown between SF tests to allow RX to finalize and re-sync
      if (millis() - stateTimer > 3000) {
        state = SEND_SYNC;
      }
      break;
    }
  }
}