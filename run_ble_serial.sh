#!/bin/bash
#

sleep 5
python3 /home/pi/bin/ble-autoconnect.py -c /home/pi/bin/autoconnect.ini 2>&1 | tee -a ~pi/data/logs/ble-serial.log

## This will forever try to keep the serial port running
#while true
#do
#    sleep 5
#    ble-serial -d E3:A0:40:C6:99:13 -t 30 -r 6e400003-b5a3-f393-e0a9-e50e24dcca9e -w 6e400002-b5a3-f393-e0a9-e50e24dcca9e
#ln -s /tmp/ttyBLE /dev/rfcomm0
#done

