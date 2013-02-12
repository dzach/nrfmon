RfMon
=======

RfMon: a software spectrum analyzer for the RFM12B tranceiver module running in an Arduino.

Use this program to visualize what the RFM12B tranceiver module hears on the 433, 868 or 915 MHz band.
It implements some basic tools to help annotate and compare link conditions for communication between Arduinos.

By monitoring the spectrum of the band where the RF12B operates you get the ability to:

- Select a vacant frequency for the network instead of using the factory set one that everybody else is using
- Adjust power level of each node so that they won't interfere with adjacent networks

The spectrum analyzer consists of two parts:

1. A sketch that needs to be uploaded to an Arduino board equipped with an RFM12B module. 
2. A TCL script that runs on a PC and connects the Arduino + RFM12B with the PC, presenting the user with a waterfall and spectrum plot of the 868MHz frequency band.

To use it you need to have a copy of tcl8.6 installed as well as the Arduino IDE with the JeeLibs library. The program has been tested with Linux, but should work on any platform where tcl8.6 exists.

Automatic comms port enumeration has been set for devices in the form of:

/dev/ttyUSB* and /dev/ttyACM*


CREDITS:

The sketch is based on the JeeLib library, https://github.com/jcw/jeelib, created by J.C.Wippler, http://jeelabs.org/2010/06/27/rfm12b-as-spectrum-analyzer/, which was itself based on an idea of loomi, back in 2010,http://talk.jeelabs.net/topic/385

LICENSE:

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
