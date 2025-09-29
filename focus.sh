#!/bin/bash
# focus.sh - show live focus measure from libcamera-hello
# Press any key to exit.

# Start libcamera-hello and process its output
libcamera-hello -t 0 --info-text "Focus measure: %focus" --nopreview 2>&1 >/dev/null |
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

