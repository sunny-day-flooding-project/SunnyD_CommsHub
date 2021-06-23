#!/bin/bash
#
# Starts data handler
#

#
# NOTE: If the sensor has changed, don't forget to change the calibration constants in config.ini
#
#rfcomm bind rfcomm0 68:27:19:F8:C6:FC
#rfcomm bind rfcomm0 68:27:19:F8:C0:9A
rfcomm bind rfcomm0 00:06:66:BC:B2:DA
sleep 10 
su pi -c 'python3 /home/pi/bin/dataHandler.py' 2>&1 | tee -a ~pi/data/logs/dataHandler.log

