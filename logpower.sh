#!/bin/bash
#set -x

thedate=`date`
thevoltage=`/usr/local/bin/lifepo4wered-cli read vin`
scaled_voltage=`echo "scale=2; $thevoltage / 1000.0" | bc -l`
echo $thedate ' ' $scaled_voltage >> /home/pi/data/logs/power.log

voltage_threshold=4700
if [[ $thevoltage -lt $voltage_threshold ]]; then
	echo $thedate ' - Power loss detected on ' `hostname`'.  Voltage: ' $scaled_voltage >> /home/pi/data/logs/Alerts
	#echo $thedate ' Power loss detected on ' `hostname` '.  Voltage: ' $scaled_voltage
fi

