#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000

static RadioEvents_t RadioEvents;
char rxpacket[50];
char txpacket[50];

uint8_t activeSF = 7;
uint16_t packetsReceived = 0;
uint32_t lastRequestTime = 0;
uint32_t batchStartTime = 0;
bool waitingForBatch = false;

// packets sent = 10. Array to track packet number recd
bool receivedPackets[11];

void resetBatchStats() {
  packetsReceived = 0;
  for (int i = 1; i <= 10; i++) {
    receivedPackets[i] = false;
  }
}

void configureRxSF(uint8_t sf) {
  activeSF = sf;
  Radio.SetTxConfig(
    MODEM_LORA, 14, 0, 0, sf, 1, 8, false, true, 0, 0, false, 3000
  );
  Radio.SetRxConfig(
    MODEM_LORA, 0, sf, 1, 0, 8, 0, false, 0, true, 0, 0, false, true
  );
  Radio.Rx(0);
}

// Outputs both human-readable text and clean CSV summary lines
void printSFSummary() {
  uint16_t missedPackets = 10 - packetsReceived;
  float plr = ((float)missedPackets / 10.0) * 100.0;

  Serial.println("\n------------------------------------------------");
  Serial.printf(" === SUMMARY FOR SF%d ===\n", activeSF);
  Serial.printf(" Total Expected : 10\n");
  Serial.printf(" Total Received : %d\n", packetsReceived);
  Serial.printf(" Total Missed   : %d\n", missedPackets);
  Serial.printf(" Packet Loss    : %.1f%%\n", plr);
  Serial.print(" Received Seq   : [ ");
  for (int i = 1; i <= 10; i++) {
    if (receivedPackets[i]) Serial.printf("%d ", i);
    else Serial.print("_ ");
  }
  Serial.println("]");
  Serial.println("------------------------------------------------");

  // CSV Summary Output Line
  Serial.printf("CSV_SUMMARY,%d,%d,%d,%.1f\n\n", activeSF, packetsReceived, missedPackets, plr);
}

void sendHandshakeRequest() {
  configureRxSF(activeSF);
  resetBatchStats();

  snprintf(txpacket, sizeof(txpacket), "REQ_SF:%d", activeSF);
  Serial.printf("\n========================================\n");
  Serial.printf("LifeBand Configured to SF%d for SF Variation and Effect on PLR/Reliability\n", activeSF);
  Serial.printf("Broadcasting Handshake Request for SF%d...\n", activeSF);
  Serial.printf("========================================\n");

  Radio.Send((uint8_t *)txpacket, strlen(txpacket));
  lastRequestTime = millis();
  batchStartTime = millis();
  waitingForBatch = true;
}

void OnTxDone(void) {
  Radio.Rx(0); // Listen immediately after sending request
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  memcpy(rxpacket, payload, size);
  rxpacket[size] = '\0';

  int pktSF = 0, pktSeq = 0;
  // Matching your custom payload tag: LBSEQ
  if (sscanf(rxpacket, "SF:%d,LBSEQ:%d", &pktSF, &pktSeq) == 2) {
    if (pktSF == activeSF && pktSeq >= 1 && pktSeq <= 10) {
      if (!receivedPackets[pktSeq]) {
        receivedPackets[pktSeq] = true;
        packetsReceived++;
      }

      // Live debug output
      Serial.printf("[RX] SF%d | Pkt %2d/10 | RSSI: %4d dBm | SNR: %3d dB\n", 
                    pktSF, pktSeq, rssi, snr);

      // Instant CSV data row export
      Serial.printf("CSV_DATA,%d,%d,%d,%d\n", pktSF, pktSeq, rssi, snr);

      // If all 10 packets arrive, print summary and move to next SF
      if (packetsReceived >= 10) {
        waitingForBatch = false;
        printSFSummary();
        delay(2000);

        activeSF++;
        if (activeSF > 12) {
          Serial.println("\n*** FULL SF7-SF12 SWEEP COMPLETE ***\n");
          activeSF = 7; // Reset back to SF7
        }

        sendHandshakeRequest();
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

  Serial.println("RX Master Ready. Starting handshake sweep in 3 seconds...");
  delay(3000);

  // CSV Column Headers for easy copying into Sheets/Excel
  Serial.println("\n--- CSV DATA LOGGING HEADER ---");
  Serial.println("Type,SF,Seq_or_Rx,RSSI_or_Missed,SNR_or_PLR");
  Serial.println("--------------------------------\n");

  sendHandshakeRequest();
}

void loop() {
  Radio.IrqProcess();

  // Dynamic Timeout based on SF Time-on-Air (SF12 takes longer than SF7)
  uint32_t timeoutThreshold = 10000 + (activeSF * 1000);

  if (waitingForBatch && (millis() - lastRequestTime > timeoutThreshold)) {
    Serial.printf("\n[TIMEOUT] Batch window closed for SF%d.\n", activeSF);
    waitingForBatch = false;

    // Report partial PLR for missed packets before advancing or retrying
    printSFSummary();

    if (packetsReceived > 0) {
      // Partial batch received; advance to next SF
      activeSF++;
      if (activeSF > 12) activeSF = 7;
      sendHandshakeRequest();
    } else {
      // No packets heard at all; retry request on same SF
      Serial.printf("No response from TX on SF%d. Retrying request...\n", activeSF);
      sendHandshakeRequest();
    }
  }
}