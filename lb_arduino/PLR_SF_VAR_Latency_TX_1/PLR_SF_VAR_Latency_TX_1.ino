#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000

// PLR with SF Variation to test Reliability and latency
// Transmit 10 packets across SF7-SF12 and in each of these record PLR and latency
// PLR = ((Ntx - Nrx)/Ntx)*100
// Total Latency= Ttx + TToA + Trx
// Calculate average across 10 packets at each SF
// Handshake included so tx-rx happens only when they are in sync on the same SFid
// Use the same code at varying distances between tx and rx
// Use the same code on varying envs - open air, env with obstacles like trees,
// urban env with buildings to mimic dense obstacles, open waters
static RadioEvents_t RadioEvents;
char rxpacket[50];
char txpacket[50];

uint8_t targetSF = 7;
uint8_t currentSeq = 0;
bool txInProgress = false;

void configureRadio(uint8_t sf) {
  Radio.SetTxConfig(MODEM_LORA, 14, 0, 0, sf, 1, 8, false, true, 0, 0, false, 3000);
  Radio.SetRxConfig(MODEM_LORA, 0, sf, 1, 0, 8, 0, false, 0, true, 0, 0, false, true);
  Radio.Rx(0);
}

void sendNextPacketInBurst() {
  currentSeq++;
  if (currentSeq <= 10) {
    snprintf(txpacket, sizeof(txpacket), "SF:%d,LBSEQ:%d", targetSF, currentSeq);
    Serial.printf("LifeBand sending packet %d/10 on SF%d...\n", currentSeq, targetSF);
    
    delay(20); 
    Radio.Send((uint8_t *)txpacket, strlen(txpacket));
  }
}

void OnTxDone(void) {
  if (txInProgress) {
    if (currentSeq < 10) {
      // Packets 1 to 9 complete -> trigger next packet transmission
      sendNextPacketInBurst();
    } else {
      // Packet 10 has physically finished transmitting over the air
      Serial.printf("Burst complete for SF%d. Reverting TX listener to SF7 baseline...\n\n", targetSF);
      txInProgress = false;
      currentSeq = 0;
      
      // Reset radio back to baseline SF7 AFTER Packet 10 finishes
      configureRadio(7);
    }
  } else {
    // Handshake ACK on SF7 finished sending; configure radio to target SF for burst
    txInProgress = true;
    currentSeq = 0;
    
    configureRadio(targetSF);
    delay(100); // Allow hardware radio state to settle
    sendNextPacketInBurst();
  }
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  if (txInProgress) return; 

  memcpy(rxpacket, payload, size);
  rxpacket[size] = '\0';

  int reqSF = 0;
  if (sscanf(rxpacket, "SYNC_SF:%d", &reqSF) == 1) {
    targetSF = reqSF;
    Serial.printf("\n[SYNC] Received handshake on SF7 for target SF%d. Sending ACK on SF7...\n", targetSF);

    // Ensure ACK is sent on baseline SF7
    configureRadio(7);
    snprintf(txpacket, sizeof(txpacket), "ACK_SF:%d", targetSF);
    Radio.Send((uint8_t *)txpacket, strlen(txpacket)); 
  }
}

void setup() {
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.TxDone = OnTxDone;
  RadioEvents.RxDone = OnRxDone;
  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);

  // Start at the baseline state: listen on SF7
  configureRadio(7);
  Serial.println("TX Slave on LifeBand Ready. Listening for RX handshakes on SF7...");
}

void loop() {
  Radio.IrqProcess();
}