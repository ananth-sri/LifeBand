#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000

// ---------------------------------------------------------------------------
// Must match the TX board's settings EXACTLY (bandwidth, spreading factor,
// coding rate) - LoRa's physical layer requires both ends to use identical
// modulation parameters, or they simply won't hear each other at all.
//
// To test a different Spreading Factor, change LORA_SPREADING_FACTOR here
// AND the matching value in plr_tx.ino, then re-upload both.
// ---------------------------------------------------------------------------
#define LORA_BANDWIDTH 0        // 0 = 125 kHz
#define LORA_SPREADING_FACTOR 7 // 7 (fast/short range) through 12 (slow/long range)
#define LORA_CODINGRATE 1       // 1 = 4/5

// Program:
// receive LBSEQ:<count> packet sent by the tx code
// calculate PLR based on ((tx-rx)/tx)*100

// Setup:
// Stationary Receiver: Set the RX node at a fixed base station.
// Mobile Transmitter: Move to specific distance intervals (e.g., 1m, 10m,
//   100m, 500m, 1km, 2km, 3km, 5km, 8km - space distances out roughly
//   logarithmically, not linearly, since RF loss follows that pattern).
// Reset and Transmit: At each distance step, type 'R' + Enter here to
//   reset this receiver's counters, then start a fresh batch of 100 (or
//   more, at longer ranges) packets on the TX board.
// Log Data: Record the final PLR, average RSSI, and SNR printed
//   automatically when the batch completes.
// Repeat in varying environments: open air, urban settings with
//   obstructions, and open water.

char rxpacket[50];
static RadioEvents_t RadioEvents;

uint16_t totalExpected = 100; // must match TX's TOTAL_PACKETS for the batch-complete summary to trigger correctly
uint16_t packetsReceived = 0;
uint16_t lastSeqNum = 0;
uint16_t missedPackets = 0;

long rssiSum = 0;
long snrSum = 0;

void resetCounters() {
  packetsReceived = 0;
  lastSeqNum = 0;
  missedPackets = 0;
  rssiSum = 0;
  snrSum = 0;
  Serial.println("========================================");
  Serial.println("Counters RESET. Ready for next distance step.");
  Serial.println("Start a fresh batch on the TX board now.");
  Serial.println("========================================");
}

void printBatchSummary() {
  float finalPlr = ((float)missedPackets / (float)totalExpected) * 100.0;
  float avgRssi = packetsReceived > 0 ? (float)rssiSum / packetsReceived : 0;
  float avgSnr = packetsReceived > 0 ? (float)snrSum / packetsReceived : 0;

  Serial.println("");
  Serial.println("########################################");
  Serial.println("BATCH COMPLETE - RECORD THIS FOR THIS DISTANCE:");
  Serial.printf("  Packets received: %d / %d\n", packetsReceived, totalExpected);
  Serial.printf("  Packets missed:   %d\n", missedPackets);
  Serial.printf("  Final PLR:        %.2f%%\n", finalPlr);
  Serial.printf("  Average RSSI:     %.1f dBm\n", avgRssi);
  Serial.printf("  Average SNR:      %.1f dB\n", avgSnr);
  Serial.println("Type 'R' + Enter to reset, then move to the next distance.");
  Serial.println("########################################");
  Serial.println("");
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  memcpy(rxpacket, payload, size);
  rxpacket[size] = '\0';

  // Parse sequence number from payload "LBSEQ:<number>"
  int currentSeq = 0;
  if (sscanf(rxpacket, "LBSEQ:%d", &currentSeq) == 1) {
    packetsReceived++;
    rssiSum += rssi;
    snrSum += snr;

    // Calculate missed packets between the last received and current packet.
    // NOTE: this can't detect loss of the very first packet(s) this
    // receiver ever hears in a batch, since there's no prior sequence
    // number to compare against yet.
    if (lastSeqNum > 0 && currentSeq > (lastSeqNum + 1)) {
      missedPackets += (currentSeq - lastSeqNum - 1);
    }
    lastSeqNum = currentSeq;

    // Calculate PLR based on current position in sequence
    float totalExpectedSoFar = currentSeq;
    float plr = ((float)(totalExpectedSoFar - packetsReceived) / totalExpectedSoFar) * 100.0;

    Serial.println("----------------------------------------");
    Serial.printf("Received: %s\n", rxpacket);
    Serial.printf("RSSI: %d dBm | SNR: %d dB\n", rssi, snr);
    Serial.printf("Rx Count: %d / %d | Missed: %d\n", packetsReceived, currentSeq, missedPackets);
    Serial.printf("Current Packet Loss Rate (PLR): %.2f%%\n", plr);
    Serial.println("----------------------------------------");

    if (currentSeq >= totalExpected) {
      printBatchSummary();
    }
  }

  Radio.Rx(0); // Re-enter continuous RX mode
}

void setup() {
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.RxDone = OnRxDone;

  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);

  // standard practice
  Radio.SetRxConfig(
    MODEM_LORA,
    LORA_BANDWIDTH,
    LORA_SPREADING_FACTOR,
    LORA_CODINGRATE,
    0,           // Bandwidth AFC
    8,           // Preamble length
    0,           // Symbol timeout
    false,       // Fixed payload length
    0,           // Payload length
    true,        // CRC check
    0,           // Frequency hopping
    0,           // Hop period
    false,       // Invert IQ
    true         // Continuous RX
  );

  Serial.println("LoRa PLR Receiver Ready.");
  Serial.printf("Config: SF%d, BW=%s, CR=4/5\n", LORA_SPREADING_FACTOR, LORA_BANDWIDTH == 0 ? "125kHz" : "other");
  Serial.println("Type 'R' + Enter at any time to reset counters for a new distance step.");
  Serial.println("Waiting for sequence...");
  Radio.Rx(0);
}

void loop() {
  Radio.IrqProcess();

  if (Serial.available()) {
    char c = Serial.read();
    if (c == 'R' || c == 'r') {
      resetCounters();
    }
  }
}