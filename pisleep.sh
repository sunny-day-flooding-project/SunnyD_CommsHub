#!/bin/bash
set -x

# Run via cron at 4 min past the hour
# Make sure the following line is in
# /etc/rc.local to reset the value
#   lifepo4wered-cli set AUTO_BOOT 0

memsize=$(cat /proc/meminfo | grep MemTotal | awk '{print $2 }')
# if we have (less than) 512k (probably a pi 0) must reduce image requirements
if (($memsize < 524288)); then
  # Pi 0 based systems use a 12v battery
  vthresh=11000	  # scale up * 1000 to match voltage
else
  # other systems use regulated 5v power supply
  vthresh=4000	  # scale up * 1000 to match voltage
fi
 
thedate=`date`
thevoltage=`/usr/local/bin/lifepo4wered-cli read vin`
scaled_voltage=`echo "scale=2; $thevoltage / 1000.0" | bc -l`

if (($thevoltage < vthresh)); then
  echo $thedate ' - Low power detected on ' `hostname`'.  Voltage: ' $scaled_voltage >> /home/pi/data/logs/Alerts
  echo $thedate ' - Entering low power mode on ' `hostname`'.'  >> /home/pi/data/logs/Alerts
  echo $thedate ' - System will be available from minute 59 through minute 4 of each hour'  >> /home/pi/data/logs/Alerts
  /home/pi/bin/AlertMonitor.sh
  /usr/local/bin/lifepo4wered-cli set AUTO_BOOT 0
  /usr/local/bin/lifepo4wered-cli set WAKE_TIME 50
  sudo shutdown -h now
fi

