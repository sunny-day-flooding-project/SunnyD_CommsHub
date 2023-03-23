#/bin/bash

echo 'This calculates the average RSSI value from the entire file ble-serial.log'
echo 'The average can be up to a few days long, so it may not pick up recent changes.'
grep Bluefruit ~/data/logs/ble-serial.log | grep RSSI | awk '{ total += $8 } END { print total/NR }'

# Results from 2-mar-2023
# BF_01: -73.7
# NB_01: -64.2
# NB_02: -71.4
# CB_01: -79.1
# CB_02: -74.21
# CB_03: -78.9

