#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000

// PLR with SF Variation to test Reliability and latency
// Receive 10 packets across SF7-SF12 sent by TX and report SFid, packet count, PLR, 
// latency. Record summary as csv for exporting/reporting

static RadioEvents_t RadioEvents;
char rxpacket[50];
char txpacket[50];

uint8_t activeSF = 7;
uint8_t sweepCount = 0;
const uint8_t MAX_SWEEPS = 2;

uint16_t packetsReceived = 0;
uint32_t lastRequestTime = 0;
uint32_t firstPacketTime = 0;
uint32_t lastPacketTime = 0;

enum State { SYNC_INIT, WAITING_FOR_ACK, RECEIVING_BATCH, TEST_COMPLETE };
State currentState = SYNC_INIT;

bool receivedPackets[11];

void resetBatchStats() {
  packetsReceived = 0;
  firstPacketTime = 0;
  lastPacketTime = 0;
  for (int i = 1; i <= 10; i++) {
    receivedPackets[i] = false;
  }
}

void configureRadio(uint8_t sf) {
  Radio.SetTxConfig(MODEM_LORA, 14, 0, 0, sf, 1, 8, false, true, 0, 0, false, 3000);
  Radio.SetRxConfig(MODEM_LORA, 0, sf, 1, 0, 8, 0, false, 0, true, 0, 0, false, true);
  Radio.Rx(0);
}

// identify and report missed packets and PLR
void printSFSummary() {
  uint16_t missedPackets = 10 - packetsReceived;
  float plr = ((float)missedPackets / 10.0) * 100.0;

  float avgOneWayToAMs = 0.0;
  if (packetsReceived > 1 && lastPacketTime > firstPacketTime) {
    avgOneWayToAMs = (float)(lastPacketTime - firstPacketTime) / (float)(packetsReceived - 1);
  }

  Serial.println("\n------------------------------------------------");
  Serial.printf(" === SUMMARY FOR SF%d (Sweep %d/%d) ===\n", activeSF, sweepCount + 1, MAX_SWEEPS);
  Serial.printf(" Total Expected    : 10\n");
  Serial.printf(" Total Received    : %d\n", packetsReceived);
  Serial.printf(" Total Missed      : %d\n", missedPackets);
  Serial.printf(" Packet Loss Rate  : %.1f%%\n", plr);
  Serial.printf(" Avg One-Way Latency: %.2f ms / pkt\n", avgOneWayToAMs);
  Serial.print(" Received Seq      : [ ");
  for (int i = 1; i <= 10; i++) {
    if (receivedPackets[i]) Serial.printf("%d ", i);
    else Serial.print("_ ");
  }
  Serial.println("]");
  Serial.println("------------------------------------------------");

  // CSV Output Line: CSV_SUMMARY, Sweep, SF, Received, Missed, PLR_Percent, Avg_OneWay_Latency_ms
  Serial.printf("CSV_SUMMARY,%d,%d,%d,%d,%.1f,%.2f\n\n", 
                sweepCount + 1, activeSF, packetsReceived, missedPackets, plr, avgOneWayToAMs);
}

void sendSyncRequest() {
  // Always send handshake request on baseline SF7
  configureRadio(7);
  resetBatchStats();

  snprintf(txpacket, sizeof(txpacket), "SYNC_SF:%d", activeSF);
  Serial.printf("Broadcast Handshake to LifeBand TX requesting batch for SF%d...\n", activeSF);

  Radio.Send((uint8_t *)txpacket, strlen(txpacket));
  lastRequestTime = millis();
  currentState = WAITING_FOR_ACK;
}

// this is done so program exits after 2 full sweeps for testing purposes
void advanceSweep() {
  delay(1000);
  activeSF++;
  if (activeSF > 12) {
    activeSF = 7;
    sweepCount++;
    if (sweepCount >= MAX_SWEEPS) {
      currentState = TEST_COMPLETE;
      Serial.println("\n************************************************");
      Serial.println("   *** TWO FULL SWEEPS COMPLETE - STOPPING ***   ");
      Serial.println("************************************************\n");
      Radio.Sleep();
      return;
    }
  }
  sendSyncRequest();
}

void OnTxDone(void) {
  Radio.Rx(0);
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  memcpy(rxpacket, payload, size);
  rxpacket[size] = '\0';

  if (currentState == WAITING_FOR_ACK) {
    int ackSF = 0;
    if (sscanf(rxpacket, "ACK_SF:%d", &ackSF) == 1 && ackSF == activeSF) {
      Serial.printf("[SYNCED] TX acknowledged batch for SF%d. Reconfiguring RX to SF%d...\n", activeSF, activeSF);
      
      // Reconfigure RX to target SF for burst capture
      configureRadio(activeSF);
      
      currentState = RECEIVING_BATCH;
      lastRequestTime = millis();
    }
    return;
  }

  if (currentState == RECEIVING_BATCH) {
    int pktSF = 0, pktSeq = 0;
    if (sscanf(rxpacket, "SF:%d,LBSEQ:%d", &pktSF, &pktSeq) == 2) {
      if (pktSF == activeSF && pktSeq >= 1 && pktSeq <= 10) {
        uint32_t now = millis();
        if (packetsReceived == 0) firstPacketTime = now;
        lastPacketTime = now;

        if (!receivedPackets[pktSeq]) {
          receivedPackets[pktSeq] = true;
          packetsReceived++;
        }

        Serial.printf("[RX] SF%d | Pkt %2d/10 | RSSI: %4d dBm | SNR: %3d dB\n", pktSF, pktSeq, rssi, snr);
        Serial.printf("CSV_DATA,%d,%d,%d,%d,%d\n", sweepCount + 1, pktSF, pktSeq, rssi, snr);

        if (packetsReceived >= 10) {
          printSFSummary();
          advanceSweep();
        }
      }
    }
  }
}

void setup() {
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.TxDone = OnTxDone;
  RadioEvents.RxDone = OnRxDone;
  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);

  Serial.println("RX Master Initialized. Synchronizing SF7 baseline in 3 seconds...");
  delay(3000);

  Serial.println("\n--- CSV DATA LOGGING HEADER ---");
  Serial.println("Type,Sweep,SF,Seq_or_Rx,RSSI_or_Missed,SNR_or_PLR,Avg_OneWay_Latency_ms");
  Serial.println("--------------------------------\n");

  sendSyncRequest();
}

void loop() {
  if (currentState == TEST_COMPLETE) return;

  Radio.IrqProcess();

  uint32_t timeoutThreshold = 8000 + (activeSF * 1500);

  if ((currentState == WAITING_FOR_ACK || currentState == RECEIVING_BATCH) && 
      (millis() - lastRequestTime > timeoutThreshold)) {
    
    Serial.printf("[TIMEOUT] SF%d window expired.\n", activeSF);
    
    if (currentState == RECEIVING_BATCH && packetsReceived > 0) {
      printSFSummary();
      advanceSweep();
    } else {
      Serial.printf("Retrying handshake on SF7 for SF%d...\n", activeSF);
      sendSyncRequest();
    }
  }
}