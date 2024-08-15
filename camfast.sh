#!/bin/bash
# This is called by schedule_camfast.sh
# It takes arguments for endtime and enddate

#set -x


#image period in seconds
PERIOD=30

# Check if exactly two arguments are provided
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 'HH:MM:SS' 'YYYY-MM-DD'"
  exit 1
fi

# Read the time and date from the command line arguments
time="$1"
date="$2"

# Combine the time and date into a single datetime string
input_datetime="$time $date"

# Convert the date and time to seconds since epoch
STOPAT=$(date -d "$input_datetime" +%s 2>/dev/null)

# Check if the conversion was successful
if [ $? -ne 0 ]; then
  echo "Error: Invalid date/time format"
  exit 1
fi

while [ "$(date +%s)" -lt "$STOPAT" ]; do
  sleep $PERIOD &
  /home/pi/bin/webcam.sh
  wait # for sleep
done
