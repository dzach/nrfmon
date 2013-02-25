// RfMon, a software spectrum analyzer
// http://jeelabs.net/boards/6/topics/715
// (C) 2013, D.Zachariadis

#include <JeeLib.h>

/*
  Change the last part in the next line to reflect the hardware signature that'll be shown on the RfMon screen.
  The signature is a dictionary, i.e. should be pairs of key/value, where the last pair is the hardware type
*/
#define RFMON_SIGNATURE F("xcvr rf12b ver 0.6a hw JeeNode.v6")

//#define LED_PIN     9   // activity LED, comment out to disable

#define RFMON_RX 0
#define RFMON_SCAN 1
#define RFMON_XCW 2
#define RFMON_XFSK 3

#define RFMON_MINBW 1
#define RFMON_PRGID 1
#define RFMON_PRXMIT 2
#define RFMON_PRSCAN 4
#define RFMON_PRCMDS 8

// initial auto transmit delay
#define RFMON_XDELAY 10

static struct {
    byte nodeId;
    byte group;
    word FSC;
    word RCC;
    word TXC;
    word AFC;
    word zone[3];
} config;

static byte top;
static boolean num = false;
static word value, stack[RF12_MAXDATA];
static char asc[] = " .;~+=#@";
static byte ascart = 0;
static byte fsk = 0xA;

// all times are in seconds
static long ondur = 10;
static long offdur = 5;
static unsigned long xontime,xofftime;

// channel limits
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
  rf12_control((config.RCC & 0xFFF8) | level);
  delayMicroseconds(1000);
}

static void scanRSSI(word lower, word upper, word stp) {
  // find amplitude of signals within the receiving band
  byte lev0 = (config.RCC & 0x7);
  for (word c = lower; c <= upper; c += stp) {
    setChannel(c);
    byte i;
    for (i = lev0; i < 8; ++i) {
      setRSSI(i);
      if (((rf12_control(0x0000) >> 8) & 1) == 0)
        break;
    }
    if (ascart)
      Serial.print(asc[i]);
    else
      Serial.write('0' + (i<=lev0 ? 0:i));
    // user has priority. Abort this scan if we have user input
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
  rf12_onOff(1);
  while (on-- && !Serial.available())
    delay(1);
  rf12_onOff(0);
  rf12_config(0); // restore normal packet listening mode
}

static void xmitFSK(byte c) {
  byte payload[62];
  for (byte i=0; i<62; i++)
    payload[i]=c;
  // transmit untill target 'on' time is reached
  while (millis() < xofftime && ! Serial.available()) {
    while (!rf12_canSend())
      rf12_recvDone();
    rf12_sendStart(0, &payload, sizeof payload);
  }
  delay(1);
}

static word setCmdWord(word cmd) {
  // find a match for the command word
 if ((cmd & 0xF800) == 0x9000)
    config.RCC = cmd;
 else if ((cmd & 0xF800) == 0x9800)
   config.TXC = cmd;
 else if ((cmd & 0xF000) == 0xA000)
    config.FSC = cmd;
 else if ((cmd & 0xFF00) == 0xC400)
    config.AFC = cmd;
 return rf12_control(cmd);
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
    Serial.print(F(" i "));Serial.print(config.nodeId & 0x1F,DEC);Serial.print(F(" g "));Serial.print(config.group);;Serial.print(F(" mem "));Serial.print(freeRam());
  }
  // band, channel, power att.
  if (c & RFMON_PRXMIT) {
    Serial.print(F(" b "));Serial.print(config.nodeId >> 6, DEC);Serial.print(F(" c "));Serial.print(config.FSC & 0x0FFF);Serial.print(F(" p "));Serial.print(config.TXC & 0x07);
  }
  // scann settings
  if (c & RFMON_PRSCAN) {
    Serial.print(F(" s {l "));Serial.print(config.zone[0]);Serial.print(F(" u "));Serial.print(config.zone[1]);Serial.print(F(" z "));Serial.print(config.zone[2]);Serial.print(F("}"));
  }
  if (c & RFMON_PRCMDS) {  
    Serial.print(F(" RCC ")); Serial.print(config.RCC, HEX); Serial.print(F(" TXC ")); Serial.print(config.TXC, HEX); Serial.print(F(" FSC ")); Serial.print(config.FSC, HEX);
  }
}

static word readOffset() {
  // clear AFC,en to disable AFC calculation, preventing register value changing before we read it
  rf12_control(config.AFC & 0xFFFE);
  // read the frequency offset from the status word
  word st = rf12_control(0x0000); // & 0x1F;
  // reset AFC
  rf12_control(config.AFC);
  return st;
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
      // temporarily enter rx mode mode, but store the current mode
      byte mode0 = mode;
      mode = RFMON_RX;
      // signal command output
      Serial.print("< ");
      Serial.print((unsigned long)value,DEC);
      Serial.print(c);
      Serial.print(" ");
      switch (c) { 
          // a,*b,*c,d,e,f,*g, ,*i, ,k,*l, , , ,  ,q,r,s,t, ,   ,w, , ,  are used in RF12demo
          //  , , , , , ,    ,h, ,j, ,   ,m,n,o,*p, , , , ,*u,*v, ,*x,y,*z   are free to use here
          case 'r': // a series of registers to set
            if (!num) {
              printSettings(RFMON_PRCMDS);Serial.println();
              break;
            }
            Serial.print(" r {");
            setCmdWord(value);Serial.print("0x");Serial.print(value,HEX);
            if (top)
              for (byte i=0; i < top;  i++) {
                 setCmdWord(stack[i]);Serial.print(" 0x");Serial.print(value,HEX);
              }
            Serial.println(" }");
            mode = mode0;
            break;
          case 'b': // set band: 1 = 433, 2 = 868, 3 = 915
            if (num && RF12_433MHZ <= value && value <= RF12_915MHZ) {
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
            // go back to the mode we were before we got user input
            mode = mode0;
            break;
          case 'i': // set node id
            if (value) {
              config.nodeId = (config.nodeId & 0xE0) + (value & 0x1F);
            }
            printSettings(RFMON_PRGID); Serial.println();
            mode = mode0;
            break;
          case 'g': // set network group
            config.group = value;
            printSettings(RFMON_PRGID); Serial.println();
            mode=mode0;
            break;
          case 's': // set scan limits
            for (byte i=0; i<top; i++)
              config.zone[i] = stack[i];
            if (value)
              mode = rx_mode = RFMON_SCAN;
            else
              mode = rx_mode = RFMON_RX;
            // swap lower with upper if necessary
            if (config.zone[0] > config.zone[1]) {
              word tmp = config.zone[0]; config.zone[0] = config.zone[1]; config.zone[1] = tmp;
            }
            // apply RFM12B hard limits to zone
            if (config.zone[0] < 96) config.zone[0] = 96;
            if (config.zone[1] > 3903) config.zone[1] = 3903;
            printSettings(RFMON_PRSCAN);Serial.println();
            break;
          case 'p': // set xmit power level
            if (num) {
              config.TXC = (config.TXC & 0xFFF8 | (value > 7 ? 7 : value));
            }
            printSettings(RFMON_PRXMIT); Serial.println();
            mode = mode0;
            break;
          case 'x': // turn on transmitter for value seconds
            if (!value) {
              if (!num)
                value = 5;
              else { // 0x : stop the transmitter
                mode = rx_mode;
                break;
              }
            }
            // if there are more parameters to the x command, then turn on auto transmit mode
            switch (top) {
              case 0: // transmit continuous carrier for a time period and stop
                mode = RFMON_XCW;
                offdur = 0;
                break;
              case 1: // transmit CW for a time period
                offdur = stack[0];
                mode = RFMON_XCW;
                break;
              default:  // transmit fsk packets for a time period
                fsk = stack[top-2];
                offdur = stack[top-1];
                mode = RFMON_XFSK;
                break;
            }
            ondur = value;
            Serial.print("x {");Serial.print(ondur); Serial.print(" "); Serial.print(offdur); Serial.print("}");
            if (mode == RFMON_XFSK) {
              Serial.print(" fsk 0x");Serial.print(fsk,HEX);
            }
            Serial.println();
            break;
          case 'a': // turn on scan mode
            ascart = value;
            mode = rx_mode = RFMON_SCAN;
            printSettings(RFMON_PRSCAN);Serial.println();
            break;
          case 'v': // user asks for the identification string, send out all settings too
            mode = RFMON_RX;
            Serial.print(RFMON_SIGNATURE); printSettings(RFMON_PRGID | RFMON_PRXMIT | RFMON_PRSCAN); Serial.println();
            break;
          case 'o': // read frequency offset
            // exhaust input
            while (Serial.available())
              Serial.read();
            Serial.print("o ");Serial.println(readOffset(),DEC);
            break;
          default:
              break;
        }
        // if we are in receive mode xmit on duration should be 0
        if (mode == RFMON_RX || mode == RFMON_SCAN)
          ondur = 0;
        value = top = num = 0;
        memset(stack, 0, sizeof stack);
    }
}

void setup () {

  Serial.begin(57600);
  Serial.println(RFMON_SIGNATURE);

  // initialize node, band and group
  config.nodeId = 0x81; // 868 MHz, node 1
  config.group = 0x00;  // default group 0
  // set defaults
  rf12_initialize(config.nodeId, config.nodeId >> 6, config.group);
  // set the rest of the config structure
  config.RCC = 0x94C0;  // Pin16 = VDI, VDIresp = fast, BW = 67kHz, LNAGain = 0dB; RSSIthreshold = -103 dBm
  config.FSC = 0xA000 | 1600;   // mid band channel
  config.TXC = 0x9807;  // FSK = 15kHz, Pwr = -17.5dB, FSK shift = positive
  config.AFC = 0xC487;  // AFC follow VDI, no limit, !st, !fi,oe,en 
  config.zone[0] = 96;
  config.zone[1] = 3903;
  config.zone[2] = 9;
  xontime = millis() + RFMON_XDELAY * 1000;
  mode = RFMON_XCW;
}

void loop () {

  while (Serial.available()) {
    // we are connected to a computer, parse user input
    handleInput(Serial.read());
  }
  // check if its time to turn on auto transmit
  if (ondur > 0) {
    // start transmitting if time has come
    if (millis() > xontime) {
      // calculate when to stop transmitting
      xofftime = millis() + ondur * 1000;
      if (mode == RFMON_XCW)
        xmitOn(ondur * 1000);
      else
        xmitFSK(fsk);
      // an offdur of 0 means we will fire just one shot
      // and then we are done with this transmission
      if (offdur == 0) {
        ondur = 0;
        mode = rx_mode;
      }
      else {
        // repeat on/off sequence
        xontime = millis() + offdur * 1000;
      }
      // notify user
      Serial.print("< ");Serial.print(ondur);Serial.print("x");printSettings(RFMON_PRCMDS | RFMON_PRXMIT);Serial.println();
    }
  }
  else if (mode == RFMON_SCAN) {
    scanRSSI(config.zone[0], config.zone[1], config.zone[2]);
  }
}
