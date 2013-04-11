// rf12bert, transmit test BER test packets using FSK modulation with the RFM12B transceiver module
// http://jeelabs.net/boards/6/topics/715
// (C) 2013, D.Zachariadis

#include <JeeLib.h>

#define RFMON_PLEN 47
// auto transmit period
#define RFMON_XDELAY 500
#define RFMON_FSKSYM 0x55

static struct {
    word FSC;
    word RCC;
    word TXC;
    word DRC;
} config;

static byte payload[RFMON_PLEN];
static word pcnt = 128;
static unsigned long time; 

static void activityLed (byte on) {
#ifdef LED_PIN
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, !on);
#endif
}

static void xmitFSK() {
    // transmit untill target 'on' time is reached
  for (byte j=0; j < pcnt; j++) {
    // packet number
    payload[0] = j;
    while (!rf12_canSend()) 
      rf12_recvDone();
    rf12_sendStart(0, &payload, sizeof payload);
  }
}

// custom settings overriding JeeLib's rf12_initialize() ones
static void rfmon_reset () {
  // set the config structure
  config.RCC = 0x94A0;  // Pin16 = VDI, VDIresp = fast, BW = 134kHz, LNAGain = 0dB; RSSIthreshold = -103 dBm
  config.TXC = 0x9857;  // FSK = 90kHz, Pwr = -17.5dB, FSK shift = positive
  config.FSC = 0xA000 | 1600;   // mid band channel, lowest channel = 96, highest channel = 3903
  config.DRC = 0xC600 | 6;  // R = 6, no prescale : Bit Rate 49265 bps
  // initialize registers here
  for (byte i = 0; i < sizeof(config)/sizeof(word); i++) {
    rf12_control(((word *) &config)[i]);
  }
}

void setup () {

  Serial.begin(57600);

  // set id, band and group
  rf12_initialize(1, RF12_868MHZ, 0);
  rfmon_reset();
  // prepare BERT patern as payload
  for (byte i=1; i<RFMON_PLEN; i++)
    payload[i] = RFMON_FSKSYM;
  // initial delay
  time = millis() + RFMON_XDELAY;
}

void loop () {
  // delay transmission until the time has come
  if (millis() > time) {
    xmitFSK();
    // renew delay
    time = millis() + RFMON_XDELAY;
  }
  delay(1);
}
