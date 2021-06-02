#!/bin/bash

set -x

BLUETOOTH_DIR=/var/lib/bluetooth

for CONTROLLER_DIR in ${BLUETOOTH_DIR}/*; do
  CONTROLLER_MAC=$(basename ${CONTROLLER_DIR})
  if [ -d "${CONTROLLER_DIR}" ] && [[ $CONTROLLER_MAC =~ ^([0-9A-F]{2}[:]){5}([0-9A-F]{2})$ ]] ; then
    for DEVICE_DIR in ${CONTROLLER_DIR}/*; do
      DEVICE_MAC=$(basename ${DEVICE_DIR})
      if [ -d "${DEVICE_DIR}" ] && [[ $DEVICE_MAC =~ ^([0-9A-F]{2}[:]){5}([0-9A-F]{2})$ ]] ; then
        if grep "Trusted=true" ${DEVICE_DIR}/info > /dev/null ; then
#          echo -e "select ${CONTROLLER_MAC}\nconnect ${DEVICE_MAC}\nquit" | bluetoothctl > /dev/null 2>&1
          echo -e "select ${CONTROLLER_MAC}\nconnect ${DEVICE_MAC}\nquit" 
        fi
      fi
    done
  fi
done

