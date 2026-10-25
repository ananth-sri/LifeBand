#include "LoRaWan_APP.h"
#include "Arduino.h"

#define RF_FREQUENCY    915000000 
#define PACKETS_PER_SF  10

static RadioEvents_t RadioEvents;

uint8_t currentSF = 7;
uint16_t packetsReceivedCurrentSF = 0;
bool rxPacketReceived = false;

int8_t rxRssi = 0;
int8_t rxSnr = 0;
char rxPayload[64];

struct PLRResult {
  uint8_t sf;
  uint16_t received;
  float plr;
} testSummary[6];

void configureRadioRxSF(uint8_t sf) {
  Radio.SetRxConfig(
    MODEM_LORA,
    0,            // BW 125 kHz
    sf,           // Spreading Factor (7-12)
    1,            // CR 4/5
    0, 8, 0, false, 0, true, 0, 0, true, 0
  );
  
  Serial.printf("\n========================================\n");
  Serial.printf("    Listening on Spreading Factor SF%d  \n", sf);
  Serial.printf("========================================\n");
  
  packetsReceivedCurrentSF = 0;
  Radio.Rx(0); 
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  rxRssi = rssi;
  rxSnr = snr;
  
  uint16_t copySize = (size < sizeof(rxPayload) - 1) ? size : sizeof(rxPayload) - 1;
  memcpy(rxPayload, payload, copySize);
  rxPayload[copySize] = '\0';
  
  rxPacketReceived = true;
  Radio.Rx(0); 
}

void OnRxTimeout(void) { Radio.Rx(0); }
void OnRxError(void)   { Radio.Rx(0); }

void recordSFResults(uint8_t sf, uint16_t rxCount) {
  uint8_t index = sf - 7;
  uint16_t lost = (rxCount <= PACKETS_PER_SF) ? (PACKETS_PER_SF - rxCount) : 0;
  
  testSummary[index].sf = sf;
  testSummary[index].received = rxCount;
  testSummary[index].plr = ((float)lost / (float)PACKETS_PER_SF) * 100.0f;
  
  Serial.printf("\n>>> SF%d Summary: Received %d/%d | PLR: %.1f%% <<<\n\n",
                sf, rxCount, PACKETS_PER_SF, testSummary[index].plr);
}

void setup() {
  Serial.begin(115200);
  
  // Power on Heltec V3 LoRa chip
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, LOW); 
  delay(100);

  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.RxDone = OnRxDone;
  RadioEvents.RxTimeout = OnRxTimeout;
  RadioEvents.RxError = OnRxError;

  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);
  Radio.SetPublicNetwork(false); // Match private network sync word

  configureRadioRxSF(currentSF);
  Serial.println("RX Ready. Waiting for TX...");
}

void loop() {
  Radio.IrqProcess();

  if (rxPacketReceived) {
    rxPacketReceived = false;

    int parsedSF = 0;
    int parsedSeq = 0;
    
    // Extract SF and Seq from tx payload
    if (sscanf(rxPayload, "SF:%d,LBSEQ:%d", &parsedSF, &parsedSeq) == 2) {
      
      // If packet belongs to a NEW SF (TX stepped ahead), transition immediately
      if (parsedSF != currentSF && parsedSF >= 7 && parsedSF <= 12) {
        recordSFResults(currentSF, packetsReceivedCurrentSF);
        currentSF = parsedSF;
        configureRadioRxSF(currentSF);
      }
      
      packetsReceivedCurrentSF++;
      
      Serial.printf("[RX SF%d] Payload: %s | RSSI: %d dBm | SNR: %d dB | Rx: %d/%d\n",
                    currentSF, rxPayload, rxRssi, rxSnr, packetsReceivedCurrentSF, PACKETS_PER_SF);
      
      // If all 10 packets received for this SF, step to next SF locally
      if (packetsReceivedCurrentSF >= PACKETS_PER_SF) {
        recordSFResults(currentSF, packetsReceivedCurrentSF);
        
        currentSF++;
        if (currentSF > 12) currentSF = 7; // Wrap back
        
        delay(1000); 
        configureRadioRxSF(currentSF);
      }
    }
  }
}