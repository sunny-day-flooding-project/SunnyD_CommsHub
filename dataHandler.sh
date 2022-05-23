#!/bin/bash
#
# Starts data handler
#

#
# NOTE: If the sensor has changed, don't forget to change the calibration constants in config.ini
#

#
# This section is for standard bluetooth devices (not low energy)
# (i.e. the original Sparkfun devices)
#
#rfcomm bind rfcomm0 68:27:19:F8:C6:FC
#rfcomm bind rfcomm0 68:27:19:F8:C0:9A
#rfcomm bind rfcomm0 00:06:66:BC:B2:DA

#
# This section is for BLE (bluetooth low energy) devices
# (i.e. the adafruit device, not the older Sparkfun devices)
#

# trying these next lines in rc.local
#su pi -c '/home/pi/bin/run_ble_serial.sh' &
## the above should create /tmp/ttyBLE
#sleep 10 
#sudo ln -s /tmp/ttyBLE /dev/rfcomm0

sleep 10 
( python3 /home/pi/bin/dataHandler.py 2>&1 | tee -a ~pi/data/logs/dataHandler.log ) > /dev/null &

