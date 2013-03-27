// RfMon, a software spectrum analyzer
// http://jeelabs.net/boards/6/topics/715
// (C) 2013, D.Zachariadis

#include <JeeLib.h>

/*
  Change the last part in the next line to reflect the hardware signature that'll be shown on the RfMon screen.
  The signature is a dictionary, i.e. should be pairs of key/value, where the last pair is the hardware type
*/
#define RFMON_SIGNATURE F("xcvr rf12b ver 0.7a hw JeeNode.v6")

//#define LED_PIN     9   // activity LED, comment out to disable

//#define RFMON_ARSSI 0

#define RFMON_RX 0
#define RFMON_SCAN 1
#define RFMON_XFSK 2

#define RFMON_MINBW 1
#define RFMON_PRGID 1
#define RFMON_PRXMIT 2
#define RFMON_PRSCAN 4
#define RFMON_PRCMDS 8
#define RFMON_PRXFSK 16

#define RFMON_PLEN 47
// initial auto transmit delay
#define RFMON_XDELAY 10

static struct {
    word CSC;
    word FSC;
    word RCC;
    word TXC;
    word DRC;
    word AFC;
    word FIFO;
    word PMC;
    word gbid;
    word chan;
    word zone[3];
} config;

static byte top;
static boolean num = false;
static word value, stack[RF12_MAXDATA];
static byte fsk = 0x55;
static word pcnt = 128;

static long offdur = 100;
static unsigned long xontime,xofftime;
static byte payload[RFMON_PLEN];
byte dcnt = 0;

// channel limits
static byte mode = RFMON_SCAN;
static byte rx_mode = RFMON_SCAN;
static byte quiet = 0;

#define RF_SLEEP_MODE   0x8205
#define RF_TXREG_WRITE  0xB800
#define RFM_IRQ     2
#define TXIDLE 4
#define NODE_ID 0x1F

static void activityLed (byte on) {
#ifdef LED_PIN
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, !on);
#endif
}

static void setChannel(word c) {
  config.chan = 0xA000 | (c & 0x0FFF);
  rf12_control(config.chan);
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
#if defined(RFMON_ARSSI)
    uint16_t arssi = analogRead(RFMON_ARSSI);
    if (arssi < 300)
      i = 0;
    else
      i = (arssi - 300) / ((1024 - 300)/256);
#else
    for (i = lev0; i < 8; ++i) {
      setRSSI(i);
      if (((rf12_control(0x0000) >> 8) & 1) == 0)
        break;
    }
#endif
    // binary output, escape a newline with a 0xFF
    Serial.write(i<=lev0 ? 0: i== 0x0A ? 0xFF : i);
    // escape a 0xFF with another 0xFF
    if (i==0xFF)
      Serial.write(0xFF);
    // user has priority. Abort this scan if we have user input
    if (Serial.available()) 
      break;
  }
  Serial.println();
  // restore receiver's settings
  rf12_control(config.RCC);
}

// turn carrier on for a number of seconds
static void xmitOn(unsigned long on) {
  rf12_initialize(config.gbid & 0x001F, (config.gbid >> 6) & 0x0003, config.gbid >> 8);
  rf12_control(config.FSC);
  rf12_control(config.TXC);
  rf12_onOff(1);
  while (on-- && !Serial.available())
    delay(1);
  rf12_onOff(0);
  rf12_config(0); // restore normal packet listening mode
}

static void xmitFSK() {
    // transmit untill target 'on' time is reached
  for (byte j=0; j<pcnt; j++) {
    if (Serial.available()) {
      return;
    }
    payload[0] = j;
    for (byte i=1; i<RFMON_PLEN; i++)
      payload[i]=fsk;
    while (!rf12_canSend())
      rf12_recvDone();
    rf12_sendStart(0, &payload, sizeof payload);
  }
}

static void setGroup (byte group) {
  if (group) {
    // two SYN bytes, Byte0 is group. Clear the sp bit.
    config.FIFO &= 0xFFF7;
    rf12_control(config.FIFO);
    // two SYN bytes, Byte0 is group. 
    rf12_control(0xCE00 | group);
  } else {
    // goup == 0, single SYN packet. Set the sp bit.
    config.FIFO |= 0x8;
    rf12_control(config.FIFO);
    // single SYN, 0x2D;
    rf12_control(0xCE2D);
  }
  // store composit gbid parameter
  config.gbid = (config.gbid & 0x00FF) | ((word) group) << 8;
}

static word setReg(word cmd) {
  // find a match for the command word
 if ((cmd & 0xF800) == 0x9000)
    config.RCC = cmd;
 else if ((cmd & 0xF800) == 0x9800)
   config.TXC = cmd;
 else if ((cmd & 0xF000) == 0xA000)
    config.FSC = cmd;
 else if ((cmd & 0xFF00) == 0xC400)
    config.AFC = cmd;
 else if ((cmd & 0xFF00) == 0xC600)
    config.DRC = cmd;
 else if ((cmd & 0xFF00) == 0xCA00)
    config.FIFO = cmd;
 else if ((cmd & 0xFF00) == 0x8000)
    config.CSC = cmd;
 else if ((cmd & 0xFF00) == 0xCE00)
    setGroup(cmd);
 else if ((cmd & 0xFF00) == 0x8200)
    config.PMC = cmd;
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
    Serial.print(F(" i "));Serial.print(config.gbid & 0x1F,DEC);Serial.print(F(" g "));Serial.print(config.gbid >> 8);;Serial.print(F(" mem "));Serial.print(freeRam());
  }
  // band, channel, power att.
  if (c & RFMON_PRXMIT) {
    Serial.print(F(" b "));Serial.print(config.gbid >> 6 & 0x0003, DEC);Serial.print(F(" c "));Serial.print(config.FSC & 0x0FFF);Serial.print(F(" p "));Serial.print(config.TXC & 0x07);
  }
  if (c & RFMON_PRXFSK) {
    Serial.print(F(" pcnt ")); Serial.print(pcnt); Serial.print(F(" offdur ")); Serial.print(offdur); Serial.print(F(" ")); Serial.print(F(" fsk 0x"));Serial.print(fsk,HEX);
  }
  // scann settings
  if (c & RFMON_PRSCAN) {
    Serial.print(F(" s {l "));Serial.print(config.zone[0]);Serial.print(F(" u "));Serial.print(config.zone[1]);Serial.print(F(" z "));Serial.print(config.zone[2]);Serial.print(F("}"));
  }
  if (c & RFMON_PRCMDS) {
    Serial.print(F(" r {"));
    for (byte i = 0; i < sizeof(config)/sizeof(word); i++) {
      Serial.print(" "); Serial.print(((word *) &config)[i],HEX);
    }
    Serial.println("}");
//    Serial.print(F(" RCC ")); Serial.print(config.RCC, HEX); Serial.print(F(" TXC ")); Serial.print(config.TXC, HEX); Serial.print(F(" FSC ")); Serial.print(config.FSC, HEX);
  }
}

static word readStatus() {
  // clear AFC,en to disable AFC calculation, preventing register value changing before we read it
  rf12_control(config.AFC & 0xFFFE);
  // read the frequency offset from the status word
  word st = rf12_control(0x0000); // & 0x1F;
  // reset AFC
  rf12_control(config.AFC);
  return st;
}

static int xmitData(word len,byte num) {
  if (!num) {
    len = RFMON_PLEN;
    for (byte i=0; i<len; i++)
      payload[i] = i;
  }
  else if (!value)  return 0;
  else {
    byte i=0;
    while (i<len) {
      while (Serial.available()) 
        payload[i++] = Serial.read();
    }
  }
  // send out the data
  activityLed(1);
  while (!rf12_canSend())
    rf12_recvDone();
  // 0 : no ack, RF12_HDR_ACK : ask for ack
  rf12_sendStart(0, &payload, len);
  activityLed(0);
  return len;
}

static void recvData() {
  Serial.print("< ");
  Serial.print(rf12_len);
  Serial.print(F("d d {"));
  Serial.write(rf12_grp);
  Serial.write(rf12_hdr);
  Serial.write(rf12_len);
  for (byte i = 0; i < rf12_len; ++i)
    Serial.write(rf12_data[i]);
  Serial.write(rf12_crc >> 8); // MSB first
  Serial.write(rf12_crc);
  Serial.println(F("}"));
        
  activityLed(1);
  if (RF12_WANTS_ACK) {
    rf12_sendStart(RF12_ACK_REPLY, 0, 0);
  }      
  activityLed(0);
}

// custom replacement of JeeLib rf12_initialize()
static void rfmon_reset () {
  // set the rest of the config structure
  config.RCC = 0x94A0;  // Pin16 = VDI, VDIresp = fast, BW = 134kHz, LNAGain = 0dB; RSSIthreshold = -103 dBm
  config.FSC = 0xA000 | 1600;   // mid band channel
  config.TXC = 0x9857;  // FSK = 90kHz, Pwr = -17.5dB, FSK shift = positive
  config.AFC = 0xC483;  // AFC follow VDI, no limit, !st, !fi,oe,en
  config.DRC = 0xC606;  // R = 6, no prescale : Bit Rate 49265 bps
  config.FIFO = 0xCA8B; // FIFO = 8, SYN = 1 , fill pattern, fill enable, RESET sens. low
  config.CSC = 0x80E7;  // 868 MHz band, TX reg enabled, RX FIFO enabled, 12pf xtal cap.
  config.PMC = 0x82DD;  // enable RX, RX baseband, synth, xtal osc, low batt. det., disable clock output
  
  config.zone[0] = 96;
  config.zone[1] = 3903;
  config.zone[2] = 9;
  config.gbid = 0x0081; // group 0, 868 MHz, node 1
  config.chan = 1600; 
  // initialize only registers here
  for (byte i = 0; i < sizeof(config)/sizeof(word) - 5; i++) {
    rf12_control(((word *) &config)[i]);
  }
  // now initialize group, band and band
  setGroup(config.gbid >> 8);
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
            } else if (!value) {
              rfmon_reset();
              break;
            }
            Serial.print(" r {");
            setReg(value);Serial.print("0x");Serial.print(value,HEX);
            if (top)
              for (byte i=0; i < top;  i++) {
                 setReg(stack[i]);Serial.print(" 0x");Serial.print(value,HEX);
              }
            Serial.println(" }");
            mode = mode0;
            break;
          case 'b': // set band: 1 = 433, 2 = 868, 3 = 915
            if (num && RF12_433MHZ <= value && value <= RF12_915MHZ) {
              // set config parameter
              config.gbid &= 0xFF3F | (value << 6);
              // set register
              setReg(config.CSC & 0xFFCF | value << 4);
            }
            printSettings(RFMON_PRXMIT); Serial.println();
            break;
          case 'c': // set frequency channel
            if (96 <= value && value <= 3903) {
              setChannel(value);
            }
            printSettings(RFMON_PRXMIT); Serial.println();
            // go back to the mode we were before we got user input
            mode = mode0;
            break;
          case 'i': // set node id
            if (value) {
              config.gbid = (config.gbid & 0xFFE0) | (value & 0x1F);
            }
            printSettings(RFMON_PRGID); Serial.println();
            mode = mode0;
            break;
          case 'g': // set network group
            if (num)
              setGroup((byte) value);
            printSettings(RFMON_PRGID); Serial.println();
            mode=mode0;
            break;
          case 's': // set scan limits
            // store scan zone parameters: lower chan, upper chan, scale
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
              config.TXC = (config.TXC & 0xFFF8) | (value > 7 ? 7 : value);
              setReg(config.TXC);
            }
            printSettings(RFMON_PRXMIT); Serial.println();
            mode = mode0;
            break;
          case 'x': // turn on transmitter for value packets
            if (num) {
              if (value) {
                pcnt = value;
                mode = RFMON_XFSK;
              } else 
                mode = rx_mode;
            } else // default xmit
              mode = RFMON_XFSK;
            // if there are more parameters to the x command, then turn on auto transmit mode
            switch (top) {
              case 1: // pause afet transmit for a time period
                offdur = stack[0];
                break;
              case 2:  // transmit fsk packets for a time period
                fsk = stack[0];
                offdur = stack[1];
                break;
            }
            printSettings(RFMON_PRXFSK); Serial.println();
            break;
          case 'v': // user asks for the identification string, send out all settings too
            mode = RFMON_RX;
            Serial.print(RFMON_SIGNATURE); printSettings(RFMON_PRGID | RFMON_PRXMIT | RFMON_PRSCAN); Serial.println();
            break;
          case 'o': // read frequency offset
            // exhaust input
            while (Serial.available())
              Serial.read();
            Serial.print("o ");Serial.println(readStatus(),DEC);
            break;
          case 't': // transmit data
            mode = rx_mode = RFMON_RX;
            Serial.print("t ");Serial.println(xmitData(value,num));
            break;
          case 'q': // allow bad crc packets to be reported
            if (num)
              quiet = value;
            Serial.print("q ");Serial.println(quiet);
            break;
          default:
              break;
        }
        value = top = num = 0;
        memset(stack, 0, sizeof stack);
      }
}

void setup () {

#ifdef RFMON_ARSSI
  analogReference(INTERNAL);
#endif

  Serial.begin(57600);
  Serial.println(RFMON_SIGNATURE);

  // set defaults
  config.gbid = 0x0081; // group 0, 868 MHz, node 1
  rf12_initialize(config.gbid & 0x001F, (config.gbid >> 6) & 0x0003, config.gbid >> 8);
  rfmon_reset();
  
  xofftime = millis() + RFMON_XDELAY * 1000;
  mode = RFMON_XFSK;
}

void loop () {

  while (Serial.available()) {
    // we are connected to a computer, parse user input
    handleInput(Serial.read());
  }
  // only valid packets are accepted
  if (mode == RFMON_RX) {
    if (rf12_recvDone() && (!rf12_crc || !quiet))
      recvData();
  }
  else if (mode == RFMON_SCAN) {
    scanRSSI(config.zone[0], config.zone[1], config.zone[2]);
  }
  else if (mode == RFMON_XFSK && millis() > xofftime) {
    xmitFSK();
    // notify user
    Serial.print("< ");Serial.print(pcnt);Serial.print("x"); printSettings(RFMON_PRXFSK); Serial.println();
    // pause xmitting for 1 sec
    xofftime = millis() + offdur;
  }
}
