// RfMon, a software spectrum analyzer
// http://jeelabs.net/boards/6/topics/715
// (C) 2013, D.Zachariadis

#include <JeeLib.h>

/*
  Change the last part in the next line to reflect the hardware signature that'll be shown on the RfMon screen.
  The signature is a dictionary, i.e. should be pairs of key/value, where the last pair is the hardware type
*/
#define RFMON_SIGNATURE F("xcvr rf12b ver 0.5 hw JeeNode.v6")

//#define LED_PIN     9   // activity LED, comment out to disable

#define RFMON_RX 0
#define RFMON_SCAN 1
#define RFMON_XMIT 2

#define RFMON_MINBW 1
#define RFMON_PRGID 1
#define RFMON_PRXMIT 2
#define RFMON_PRSCAN 4
#define RFMON_PRCMDS 8

typedef struct {
    byte nodeId;
    byte group;
    byte patt;
    word FSC;
    word RCC;
    word TXC;
} RF12Config;

static RF12Config config;
static byte top;
static boolean num = false;
static word value, stack[RF12_MAXDATA];
static char asc[] = " .;~+=#@";
static byte ascart = 0;

// all times are in seconds
static long ontime = 10;
static long offtime = 5;
static long xtime;

// channel limits
static word lower = 96, upper = 3903, scale = 26;
static byte mode = RFMON_SCAN;
static byte rx_mode = RFMON_SCAN;

static void activityLed (byte on) {
#ifdef LED_PIN
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, !on);
#endif
}

static void setChannel(word c) {
    rf12_control(0xA000 | c);
    rf12_recvDone();
    delay(3);
}

static void setRSSI(byte level) {
  rf12_control(config.RCC | level);
  delayMicroseconds(1000);
}

static void scanRSSI(word lower, word upper, word stp) {
  // find amplitude of signals within the receiving band
  for (word c = lower; c < upper; c += stp) {
    setChannel(c);
    byte i;
    for (i = 0; i < 8; ++i) {
      setRSSI(i);
      if (((rf12_control(0x0000) >> 8) & 1) == 0)
        break;
    }
    if (ascart)
      Serial.print(asc[i]);
    else
      Serial.write('0' + i);
    // user has priority. Abort this scan
    if (Serial.available()) 
      break;
  }
  Serial.println();
  // restore receiver's settings
  rf12_control(config.RCC);
}

// set power attenuation
static void setPower (byte patt) {
  rf12_control(config.TXC | (patt & 0x07));
}

// turn carrier on for a number of seconds
static void xmitOn(unsigned long on) {
  rf12_initialize(0, config.nodeId >> 6);
  rf12_control(config.FSC);
  rf12_control(config.TXC);
  on *= 1000;
  rf12_onOff(1);
  while(on--)
    if (!Serial.available())
      delay(1);
  rf12_onOff(0);
  rf12_config(0); // restore normal packet listening mode
  rf12_control(config.RCC);
}

static void setCmdWord(word cmd) {
  // find a match for the command word
 if ((cmd & 0xF800) == 0x9000)
    config.RCC = cmd;
 else if ((cmd & 0xF800) == 0x9800)
   config.TXC = cmd;
 else if ((cmd & 0xF000) == 0xA000)
    config.FSC = cmd;
}

int freeRam () {
  extern int __heap_start, *__brkval; 
  int v; 
  return (int) &v - (__brkval == 0 ? (int) &__heap_start : (int) __brkval); 
}

static void printSettings (byte c) {
  // all cases fall through

  // id, group
  if (c & RFMON_PRGID){
    Serial.print(" i ");Serial.print(config.nodeId & 0x1F,DEC);Serial.print(" g ");Serial.print(config.group);;Serial.print(" mem ");Serial.print(freeRam());
  }
  // band, channel, power att.
  if (c & RFMON_PRXMIT) {
    Serial.print(" b ");Serial.print(config.nodeId >> 6, DEC);Serial.print(" c ");Serial.print(config.FSC & 0x0FFF);Serial.print(" p ");Serial.print(config.TXC & 0x07);
  }
  // scann settings
  if (c & RFMON_PRSCAN) {
    Serial.print(" l ");Serial.print(lower);Serial.print(" u ");Serial.print(upper);Serial.print(" z ");Serial.print(scale);
  }
  if (c & RFMON_PRCMDS) {  
    Serial.print(" RCC "); Serial.print(config.RCC, HEX); Serial.print(" TXC "); Serial.print(config.TXC, HEX); Serial.print(" FSC "); Serial.print(config.FSC, HEX);
  }
}

static void handleInput (char c) {
    if ('0' <= c && c <= '9') {
      value = 10 * value + c - '0';
      // used to distinguish 0 values from empty commands
      num = true;
    } else if (c == ',') {
      if (top < sizeof stack)
        stack[top++] = value;
      value = 0;
    } else if ('a' <= c && c <='z') {
      // enter rx mode mode
      mode = rx_mode;
      // stop auto transmit
      ontime = -1;
      // signal command output
      Serial.print("<");
      Serial.print((int) value);
      Serial.print(c);
      Serial.print(" ");
      switch (c) { 
          // a,b,c,d,e,f,g, ,i, ,k,l, , , , ,q,r,s,t, , ,w, , ,  are used in RF12demo
          //  , , , , , , ,h, ,j, , ,m,n,o,p, , , , ,u,v, ,x,y,z   are free to use here
          case 'r': // a series of registers to set
            if (!num) {
              printSettings(RFMON_PRCMDS);Serial.println();
              break;
            }
            rf12_control(value);
            setCmdWord(value);
            Serial.print("0x");
            Serial.println(value,HEX);
            if (top)
              for (byte i=0; i < top;  i++) {
                rf12_control(stack[i]);
                setCmdWord(stack[i]);
                Serial.print("0x");
                Serial.println(stack[i],HEX);
              }
            break;
          case 'b': // set band: 1 = 433, 2 = 868, 3 = 915

              if (RF12_433MHZ <= value && value <= RF12_915MHZ) {
                config.nodeId = (config.nodeId & 0x3F) + (value << 6);
              }
              printSettings(RFMON_PRXMIT); Serial.println();
              break;
          case 'c': // set frequency channel
              if (96 <= value && value <= 3903) {
                config.FSC = 0xA000 | value;
                rf12_control(config.FSC);
              }
              printSettings(RFMON_PRXMIT); Serial.println();
              break;
          case 'i': // set node id
              if (value) {
                config.nodeId = (config.nodeId & 0xE0) + (value & 0x1F);
              }
              printSettings(RFMON_PRGID); Serial.println();
              break;
          case 'g': // set network group
              config.group = value;
              printSettings(RFMON_PRGID); Serial.println();
              break;
          case 'l': // set low freq for scanning
              lower = (value < 96 ? 96 : value > (upper - RFMON_MINBW) ? (upper - RFMON_MINBW) : value);
              mode = RFMON_RX;
              printSettings(RFMON_PRSCAN);Serial.println();
              break;
          case 'u': // set low freq for scanning
              upper = (value > 3903 ? 3903 : value < (lower + RFMON_MINBW) ? (lower + RFMON_MINBW) : value);
              mode = RFMON_RX;
              printSettings(RFMON_PRSCAN);Serial.println();
              break;
          case 'z': // set step for scanning
              scale = (value <= 0 ? scale : value);
              mode = RFMON_RX;
              printSettings(RFMON_PRSCAN);Serial.println();
              break;
          case 'p': // set xmit power level
              if (num) {
                config.TXC = config.TXC & 0xFFF8 | (value > 7 ? 7 : value);
              }
              printSettings(RFMON_PRXMIT); Serial.println();
              break;
          case 'x': // turn on transmitter for value seconds
              activityLed(1);
              // if there is a second parameter to the x command, then turn on auto transmit mode
              if (top) {
                mode = RFMON_XMIT;
                ontime = value;
                offtime = stack[0];
                Serial.print("x {");Serial.print(value); Serial.print(" "); Serial.print(stack[0]); Serial.println("}");
                break;
              }
              // turn on transmitter, 5s default
              if (!value)
                value = 5;
              // TODO: FSK transmission
              xmitOn(value);
              Serial.print("x ");Serial.print(value); printSettings(RFMON_PRXMIT); Serial.println();
              break;
          case 's': // turn on scan mode
              ascart = value;
              mode = rx_mode = RFMON_SCAN;
              printSettings(RFMON_PRSCAN);Serial.println();
              break;
          case 'v': // user asks for the identification string, send out all settings too
              Serial.print(RFMON_SIGNATURE); printSettings(RFMON_PRGID | RFMON_PRXMIT | RFMON_PRSCAN); Serial.println();
              break;
          default:
              break;
        }
        value = top = num = 0;
        memset(stack, 0, sizeof stack);
    }
}

void setup () {

  Serial.begin(57600);
  Serial.println(RFMON_SIGNATURE);

  // initialize confi structure
  config.nodeId = 0x81; // 868 MHz, node 1
  config.group = 0x00;  // default group 0
  config.RCC = 0x94C0;  // Pin16 = VDI, VDIresp = fast, BW = 67kHz, LNAGain = 0dB; RSSIthreshold = -103 dBm
  config.FSC = 0xA000 | 1600;   // mid band channel
  config.TXC = 0x9807;  // FSK = 15kHz, Pwr = -17.5dB, FSK shift = positive
  // set defaults
  rf12_config(0);
  xtime = millis() + 10 * 1000;
}

void loop () {

  while (Serial.available()) {
    // we are connected to a computer, parse user input
    handleInput(Serial.read());
  }
  // check if its time to turn on auto transmit
  if (ontime >= 0 && millis() > xtime) {
    mode = RFMON_XMIT;
    xmitOn(ontime);
    xtime = millis() + offtime * 1000;
  }
  else if (mode == RFMON_SCAN) {
    scanRSSI(lower, upper, scale);
  }
}
