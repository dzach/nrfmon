// RfMonCW : transmit unmodulated Continuous Wave signals
#include <JeeLib.h>

//#define LED_PIN     9   // activity LED, comment out to disable


typedef struct {
    byte nodeId;
    byte group;
    word FSC;
    word TXC;
    word crc;
} RF12Config;

static RF12Config config;

// all times are in seconds
static long ontime = 10;
static long offtime = 5;
static long xtime = 0;

static void activityLed (byte on) {
#ifdef LED_PIN
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, !on);
#endif
}

// turn carrier on/off for a number of seconds
static void xmitOn(unsigned long on) {
  rf12_initialize(0, config.nodeId >> 6);
  // reset our settings because rf12_initialize changed them
  rf12_control(config.FSC);
  rf12_control(config.TXC);
  on *= 1000;
  // turn on xmitter
  rf12_onOff(1);
  while(on--) delay(1);
  // turn off xmitter
  rf12_onOff(0);
  rf12_config(0);
}

void setup () {
  // initialize config structure
  config.nodeId = 0x80;        // 868 MHz, node 0
  config.group = 0x00;         // default group 0
  config.FSC = 0xA000 | 1600;  // mid band channel
  config.TXC = 0x9807;         // FSK = 15kHz, Pwr = -17.5dB, FSK shift = positive
}

void loop () {
  // check if its time to turn on auto transmit
  if (millis() > xtime) {
    activityLed (1);
    xmitOn(ontime);
    activityLed (0);
    xtime = millis() + offtime * 1000;
  }
}
