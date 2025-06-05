#!/bin/bash
set -x

# This was my best shot at turning off LEDs at night so they wouldn't interfere
# with long night exposures with the camera.  I have no access to the SixFab PWR 
# and STAT LEDs, nor do I have access to the lifepo4wered/pi+ CHRG LED.

# Function to turn off LEDS
turn_off_leds() {
    for LED_PATH in "${LED_PATHS[@]}"; do
        echo 0 | sudo tee "$LED_PATH"/brightness
    done
    lifepo4wered-cli set LED_STATE 0
}

# Function to turn on LEDS
turn_on_leds() {
    for LED_PATH in "${LED_PATHS[@]}"; do
        echo 255 | sudo tee "$LED_PATH"/brightness
    done
    lifepo4wered-cli set LED_STATE 1
}

# Get Raspberry Pi model
MODEL=$(cat /proc/device-tree/model | tr -d '\0')

LATITUDE=$(confget -f /home/pi/bin/config.ini LATITUDE)
if [[ -z "$LATITUDE" ]]; then
    LATITUDE='35N'
fi

LONGITUDE=$(confget -f /home/pi/bin/config.ini LONGITUDE)
if [[ -z "$LONGITUDE" ]]; then
    LONGITUDE='77W'
fi

DAY_OR_NIGHT=$(/home/pi/bin/sunwait poll "$LATITUDE" "$LONGITUDE")

# Set LED paths based on the model
if [[ "$MODEL" == *"Raspberry Pi Zero 2 W"* ]]; then
    LED_PATHS=("/sys/class/leds/ACT")
elif [[ "$MODEL" == *"Raspberry Pi 4 Model B"* ]]; then
    LED_PATHS=("/sys/class/leds/ACT" "/sys/class/leds/PWR")  # Include both LEDs for Pi 4
else
    echo "Unsupported Raspberry Pi model: $MODEL"
    exit 1
fi

# Control LEDs based on light
if [ "$DAY_OR_NIGHT" == "NIGHT" ]; then
    turn_off_leds
else
    turn_on_leds
fi
