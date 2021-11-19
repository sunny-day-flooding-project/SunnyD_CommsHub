#!/bin/bash
#
# This will forever try to keep the serial port running
while true
do
    sleep 25
    ble-serial -d E3:A0:40:C6:99:13 -r 6e400003-b5a3-f393-e0a9-e50e24dcca9e -w 6e400002-b5a3-f393-e0a9-e50e24dcca9e
ln -s /tmp/ttyBLE /dev/rfcomm0
done

