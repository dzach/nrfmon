nRfMon
=======

A software spectrum analyzer for the RFM12B transceiver module running in an Arduino.

![Screenshot](https://raw.github.com/dzach/nrfmon/master/images/nrfmon_scan.png)
Scan mode

![Screenshot](https://raw.github.com/dzach/nrfmon/master/images/nrfmon_BERT.png)
Bit Error Rate mode


Use this program to visualize what the RFM12B transceiver module hears on the 433, 868 or 915 MHz band.
It implements some basic tools to help annotate and compare link conditions for communication between Arduinos.

By monitoring the spectrum of the band where the RF12B operates you get the ability to:

- Select a vacant frequency for the network instead of using the factory set one that everybody else is using
- Adjust power level of each node so that they won't interfere with adjacent networks

The spectrum analyzer consists of two parts:

1. A sketch that needs to be uploaded to an Arduino board equipped with an RFM12B module. 
2. A TCL script that runs on a PC and connects the Arduino + RFM12B with the PC, presenting the user with a waterfall and spectrum plot of the frequency band in use.

To use it you need to have a copy of tcl8.6 installed as well as the Arduino IDE with the JeeLibs library. The program has been tested with Linux, Mac OS and Windows and should work on any platform for which tcl/tk v8.6 exists. If you do not have tcl/tk v8.6 installed you can use one of the executable binaries provided below.

Select the port where the RFM12B carrying node is commected. Automatic comms port enumeration has been set for serial communications ports in the form:

/dev/ttyUSB* and /dev/ttyACM* /dev/tty.usbserial*

Ready to use binaries (no need to install tcl8.6):
*   Linux x86 : https://raw.github.com/dzach/nrfmon/master/binaries/nrfmon
*   Windows x86 : https://github.com/dzach/nrfmon/blob/master/binaries/nrfmon.exe?raw=true

NOTE:

The output of the RFM12B module is 5dBm on a matched 50 Ohm termination, i.e. it is a low power transmitter. While use of the RFM12B is allowed in specific bands around the world, one should always read and abide by the rules and laws of each country, when conducting low power tests on radio frequencies, even with such low power levels.

CREDITS:

The sketch is based on the JeeLib library, https://github.com/jcw/jeelib, created by J.C.Wippler, http://jeelabs.org/2010/06/27/rfm12b-as-spectrum-analyzer/, which was itself based on an idea of loomi, back in 2010,http://talk.jeelabs.net/topic/385

For more details on how this monitor works, check this long forum thread: https://jeelabs.net/boards/6/topics/715?page=1&r=1521.

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
