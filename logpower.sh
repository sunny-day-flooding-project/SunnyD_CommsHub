#!/bin/sh

thedate=`date`
thevoltage=`/usr/local/bin/lifepo4wered-cli read vin`
echo $thedate ' ' $thevoltage >> /home/pi/data/logs/power.log
