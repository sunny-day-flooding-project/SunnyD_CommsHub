#!/bin/bash
# Run Wi-Fi priority check on interface events
#
# This file is only meant for systems set up for using Network manager
# which for us is OS 13, Trixie or newer.  It will be installed installed
# in /etc/NetworkManager/dispatcher.d

IFACE="$1"
STATUS="$2"

if [[ "$IFACE" == wlan* ]] && [[ "$STATUS" == up ]]; then
    /usr/local/bin/wifi-priority-switch.sh
fi
