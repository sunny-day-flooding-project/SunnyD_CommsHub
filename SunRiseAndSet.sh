#!/bin/bash

# Set the latitude and longitude of the location somewhere a bit south of New Bern
LATITUDE=35.0
LONGITUDE=-77.0

# Get the current date and time
CURRENT_DATE=$(date +%F)
CURRENT_TIME=$(date +%T)

# Calculate the approximate sunrise and sunset times
SUNRISE_TIME=$(date -d "$(echo "scale=2; (6 - ($LONGITUDE / 15))" | bc) hours" +%T)
SUNSET_TIME=$(date -d "$(echo "scale=2; (18 - ($LONGITUDE / 15))" | bc) hours" +%T)

# Compare the current time with the sunrise and sunset times
if [ "$CURRENT_TIME" \< "$SUNRISE_TIME" ]; then
  echo "It is currently nighttime. The sun will rise at approximately $SUNRISE_TIME."
elif [ "$CURRENT_TIME" \> "$SUNSET_TIME" ]; then
  echo "It is currently nighttime. The sun set at approximately $SUNSET_TIME."
else
  echo "It is currently daytime. The sun will set at approximately $SUNSET_TIME."
fi