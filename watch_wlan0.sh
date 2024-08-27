#!/bin/bash

# Function to check if Wi-Fi is connected
check_wifi_connected() {
    # Check for an active Wi-Fi connection by seeing if an IP address is assigned to wlan0
    if ip a show wlan0 | grep -q "inet "; then
        return 0  # Wi-Fi is connected
    else
        return 1  # Wi-Fi is not connected
    fi
}

# Function to check if wwan0 is up
is_wwan0_up() {
    if ip a show wwan0 | grep -q "state DOWN"; then
        return 1  # wwan0 is down
    else
        return 0  # wwan0 is up
    fi
}

# Function to bring wwan0 down
bring_wwan0_down() {
    if is_wwan0_up; then
        echo "wwan0 is up. Bringing it down..."
        sudo ifconfig wwan0 down
    else
        echo "wwan0 is already down."
    fi
}

# Function to bring wwan0 up
bring_wwan0_up() {
    if is_wwan0_up; then
        echo "wwan0 is already up."
    else
        echo "wwan0 is down. Bringing it up..."
        sudo ifconfig wwan0 up
    fi
}

# Main script logic

if ip a show | grep -q "wwan0"; then
    while true
    do
        if check_wifi_connected; then
            echo "Wi-Fi is connected."
            bring_wwan0_down
        else
            echo "Wi-Fi is not connected."
            bring_wwan0_up
        fi
        sleep 10
    done
fi
