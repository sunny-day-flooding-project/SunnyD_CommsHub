#!/bin/bash
#
# Starts data handler
#
rfcomm bind rfcomm0 00:06:66:BC:B2:DA
sleep 10 
su pi -c 'python3 /home/pi/bin/dataHandler.py' 2>&1 | tee -a ~pi/data/logs/dataHandler.log

