#!/bin/bash
#
# Use the LifePO4wered board to shut off power to the pi for 1 minute
#
# NOTE there is a bit of a race in that this script must complete and return
# the 0 (SUCCESS) exit code to the watchdog daemon before the shutdown command
# kills it otherwise the watchdog will issue a reboot which will not do the 
# power cycle via the LifePO4wered board.  If this ever becomes a problem, the
# shutdown command can be issued with a delay in minutes such as
# 'sudo shutdown -h +1' with the +1 argument instead of 'now'.
#
thedate=`date`
echo $thedate ' - Power cycle script called on ' `hostname`'. Possible watchdog-based reboot.' >> /home/pi/data/logs/Alerts
/home/pi/bin/AlertMonitor.sh

/usr/local/bin/lifepo4wered-cli set AUTO_BOOT 0
/usr/local/bin/lifepo4wered-cli set WAKE_TIME 1
sudo shutdown -h now
exit 0
