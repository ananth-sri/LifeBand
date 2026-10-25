// SF testing - RX
#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY 915000000

// >>> SET THIS BEFORE EACH TEST RUN <
#define DISTANCE_M 100
#define PACKETS_PER_SF 10

char rxpacket[50];
static RadioEvents_t RadioEvents;

uint8_t activeSF = 7;
uint32_t lastRxTime = 0;
const uint32_t SF_TIMEOUT_MS = 5000; // fallback only, in case a whole SF pass is totally lost

uint16_t receivedPerSF[6] = {0};
int32_t rssiSum[6] = {0};
int32_t snrSum[6] = {0};
bool reportedPerSF[6] = {false};

bool csvHeaderPrinted = false;

volatile bool pendingPrint = false;
int lastSF = 0, lastSeq = 0, lastRssi = 0, lastSnr = 0;

void printCsvHeader() {
  Serial.println("distance_m,sf,seq,rssi_dbm,snr_db,event");
  csvHeaderPrinted = true;
}

void reportPLR(uint8_t sfIndex) {
  if (reportedPerSF[sfIndex]) return;
  reportedPerSF[sfIndex] = true;

  uint8_t sf = sfIndex + 7;
  uint16_t rec = receivedPerSF[sfIndex];
  float plr = 100.0f * (PACKETS_PER_SF - rec) / PACKETS_PER_SF;
  float avgRssi = rec > 0 ? (float)rssiSum[sfIndex] / rec : 0;
  float avgSnr = rec > 0 ? (float)snrSum[sfIndex] / rec : 0;

  Serial.printf("=== SF%d SUMMARY | dist=%dm | expected=%d received=%d | PLR=%.1f%% | avgRSSI=%.1fdBm | avgSNR=%.1fdB ===\n",
                sf, DISTANCE_M, PACKETS_PER_SF, rec, plr, avgRssi, avgSnr);
}

void configureRxSF(uint8_t sf) {
  uint8_t idx = sf - 7;
  receivedPerSF[idx] = 0;
  rssiSum[idx] = 0;
  snrSum[idx] = 0;
  reportedPerSF[idx] = false;

  Radio.SetRxConfig(
    MODEM_LORA,
    0, sf, 1,
    0, 8, 0, false, 0, true, 0, 0, false, true
  );
  Radio.Rx(0);
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  lastRxTime = millis();
  memcpy(rxpacket, payload, size);
  rxpacket[size] = '\0';

  int pktSF = 0, pktSeq = 0;
  bool parsed = (sscanf(rxpacket, "SF:%d,LBSEQ:%d", &pktSF, &pktSeq) == 2 && pktSF >= 7 && pktSF <= 12);

  if (parsed) {
    uint8_t idx = pktSF - 7;

    receivedPerSF[idx]++;
    rssiSum[idx] += rssi;
    snrSum[idx] += snr;

    lastSF = pktSF; lastSeq = pktSeq; lastRssi = rssi; lastSnr = snr;
    pendingPrint = true;

    if (pktSeq == PACKETS_PER_SF) {
      reportPLR(idx);
      activeSF = (pktSF >= 12) ? 7 : pktSF + 1;
      configureRxSF(activeSF);
      return;
    }
  }

  Radio.Rx(0);
}

void setup() {
  Serial.begin(115200);
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.RxDone = OnRxDone;
  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);

  configureRxSF(activeSF);
  Serial.printf("LoRa RX Ready. Distance=%dm. Listening on SF%d...\n", DISTANCE_M, activeSF);
  lastRxTime = millis();
}

void loop() {
  Radio.IrqProcess();

  if (pendingPrint) {
    pendingPrint = false;
    if (!csvHeaderPrinted) printCsvHeader();
    Serial.printf("%d,%d,%d,%d,%d,RX\n", DISTANCE_M, lastSF, lastSeq, lastRssi, lastSnr);
    Serial.printf("[RX SUCCESS] SF: %d | Packet: %d/%d | RSSI: %d dBm | SNR: %d dB\n",
                  lastSF, lastSeq, PACKETS_PER_SF, lastRssi, lastSnr);
  }

  if (millis() - lastRxTime > SF_TIMEOUT_MS) {
    reportPLR(activeSF - 7);

    lastRxTime = millis();
    activeSF++;
    if (activeSF > 12) activeSF = 7;

    Serial.printf("No packet heard (timeout). Scanning on SF%d...\n", activeSF);
    configureRxSF(activeSF);
  }
}


