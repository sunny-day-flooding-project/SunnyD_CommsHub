#!/bin/bash
set -x

ALERT_RECIPIENTS=`confget -f /home/pi/bin/config.ini ALERT_RECIPIENTS`
if [[ -z "$ALERT_RECIPIENTS" ]]
then
    echo $'Did not find config value ALERT_RECIPIENTS.  Exiting\n'
    exit 1
fi

alert_file="/home/pi/data/logs/Alerts"
if test -f $alert_file; then
  # add \r\n to each line
  alert_text=$(sed 's/$/\\r\\n/' $alert_file)
  echo -e "Subject: `hostname` Alerts\r\n\r\n" $alert_text
  echo -e "Subject: `hostname` Alerts\r\n\r\n$alert_text" | msmtp --debug --from=`hostname` -t $ALERT_RECIPIENTS
  
  cat $alert_file >> /home/pi/data/logs/alert.log
  rm $alert_file
fi
