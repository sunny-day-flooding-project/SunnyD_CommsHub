#!/bin/bash
# focus.sh - show live focus measure from libcamera-hello
# Press any key to exit.

# --- Function to Determine Camera Command ---
get_camera_command() {
    # Check for the newest command (Bookworm/Trixie and later)
    if command -v rpicam-still &> /dev/null; then
        echo "rpicam-hello"
    # Check for the intermediate command (Bullseye)
    elif command -v libcamera-still &> /dev/null; then
        echo "libcamera-hello"
    # Fallback to the old command (Buster/Legacy)
    elif command -v raspistill &> /dev/null; then
        echo "raspistill"
    else
        echo "" # No camera command found
    fi
}

# --- Script Logic ---
CAMERA_CMD=$(get_camera_command)

if [ "$CAMERA_CMD" = "raspistill" ]; then
	echo "Unsupported on this OS version"
else
	# Start libcamera-hello and process its output
	$CAMERA_CMD -t 0 --info-text "Focus measure: %focus" --nopreview 2>&1 >/dev/null |
	grep --line-buffered "Focus measure" |
	while read -r val; do
		printf "\r%s" "$val"
	done &
	pid=$!

	# Wait for any key press
	echo -e "\nPress any key to exit..."
	read -n 1 -s
	kill $pid 2>/dev/null
	echo
fi
