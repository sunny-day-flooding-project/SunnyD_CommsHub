#!/bin/bash

atcom at\$gpsp=1

while true
  do
    atcom at\$gpsacp | grep GPSACP >> cellSignal.log
    atcom at+creg? | grep CREG >> cellSignal.log
    atcom at+cops? | grep COPS >> cellSignal.log
    atcom at+csq | grep CSQ >> cellSignal.log
    sleep 5
  done
