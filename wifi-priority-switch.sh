#!/bin/bash
# Script to switch to the highest-priority visible Wi-Fi
#
# This file is only meant for systems set up for using Network manager
# which for us is OS 13, Trixie or newer.  It will be installed installed
# in /usr/local/bin and run by systemd every n (30) seconds
#

# --- Check OS Version ---
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$VERSION_CODENAME" != "trixie" ]]; then
        # If VERSION_CODENAME is lexically less than 'trixie'
        declare -A DEBIAN_ORDER=([buster]=10 [bullseye]=11 [bookworm]=12 [trixie]=13 [forky]=14)
        CURRENT=${DEBIAN_ORDER[$VERSION_CODENAME]:-0}
        if (( CURRENT < 13 )); then
            echo "❌ This script is only supported on Raspberry Pi OS Trixie (Debian 13) or newer."
            echo "Detected: $PRETTY_NAME"
            exit 1
        fi
    fi
else
    echo "❌ Unable to determine OS version (missing /etc/os-release)."
    exit 1
fi

echo "✅ OS check passed: running on $PRETTY_NAME"


# Wi-Fi interface
IFACE="wlan0"

# Get the currently connected SSID
CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d: -f2)

# Get all saved Wi-Fi connections with autoconnect-priority
mapfile -t SAVED_WIFI < <(
nmcli -t -f name,type,autoconnect-priority connection show | while IFS=: read -r NAME TYPE PRIORITY; do
    if [[ "$TYPE" == "802-11-wireless" ]]; then
        echo "$NAME:$PRIORITY"
    fi
done | sort -t: -k2 -nr
)

for ENTRY in "${SAVED_WIFI[@]}"; do
    TARGET_SSID=$(echo "$ENTRY" | cut -d: -f1)
    TARGET_PRIORITY=$(echo "$ENTRY" | cut -d: -f2)

    # Skip if already connected
    if [[ "$TARGET_SSID" == "$CURRENT_SSID" ]]; then
        break
    fi

    # Check if the SSID is currently visible
    if nmcli -t -f ssid dev wifi | grep -qx "$TARGET_SSID"; then
        echo "Switching from '$CURRENT_SSID' to higher-priority network '$TARGET_SSID' (priority $TARGET_PRIORITY)"
        nmcli connection up "$TARGET_SSID"
        break
    fi
done
