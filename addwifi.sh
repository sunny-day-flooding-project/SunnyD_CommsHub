#!/bin/bash
# create-nmconnection.sh
# Create or replace a NetworkManager .nmconnection file with hashed PSK
# Runs only on Raspberry Pi OS Trixie (Debian 13) or newer

set -e

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

# --- Prompt for Wi-Fi details ---
read -rp "Enter SSID: " SSID
read -rsp "Enter Wi-Fi Password: " PASSWORD
echo
read -rp "Enter priority (higher number = higher priority): " PRIORITY

# --- Define connection path ---
CONN_DIR="/etc/NetworkManager/system-connections"
CONN_FILE="$CONN_DIR/${SSID// /_}.nmconnection"

# --- Check for existing connection ---
if nmcli -t -f NAME connection show | grep -Fxq "$SSID"; then
    echo "Connection '$SSID' already exists."
    read -rp "Would you like to replace it? [y/N]: " REPLACE
    if [[ "$REPLACE" =~ ^[Yy]$ ]]; then
        echo "Removing existing connection..."
        sudo nmcli connection delete "$SSID" || true
        sudo rm -f "$CONN_FILE" || true
    else
        echo "Aborting — existing connection kept."
        exit 0
    fi
fi

# --- Generate hashed PSK ---
HASHED_PSK=$(wpa_passphrase "$SSID" "$PASSWORD" | grep '^\s*psk=' | tail -n1 | cut -d= -f2)

if [[ -z "$HASHED_PSK" ]]; then
    echo "❌ Failed to generate PSK. Check your inputs."
    exit 1
fi

# --- Create the .nmconnection file ---
sudo bash -c "cat > '$CONN_FILE' <<EOF
[connection]
id=$SSID
uuid=$(uuidgen)
type=802-11-wireless
autoconnect=true
autoconnect-priority=$PRIORITY
permissions=

[wifi]
mode=infrastructure
ssid=$SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$HASHED_PSK

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto
EOF"

# --- Secure permissions ---
sudo chmod 600 "$CONN_FILE"

echo "✅ Created/updated secure connection file:"
echo "   $CONN_FILE"

echo "Reloading NetworkManager..."
sudo nmcli connection reload

echo "✅ Connection '$SSID' created with priority $PRIORITY."
