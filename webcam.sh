#!/bin/bash
set -x

# --- Configuration Variables ---
PIC_DIR="/home/pi/webcam/"

LATITUDE=$(confget -f /home/pi/bin/config.ini LATITUDE)
if [[ -z "$LATITUDE" ]]; then
	LATITUDE='35N'
fi

LONGITUDE=$(confget -f /home/pi/bin/config.ini LONGITUDE)
if [[ -z "$LONGITUDE" ]]; then
	LONGITUDE='77W'
fi

CAMERA_ROTATION=$(confget -f /home/pi/bin/config.ini CAMERA_ROTATION)
if [[ -z "$CAMERA_ROTATION" ]]; then
	CAMERA_ROTATION='0'
fi

# --- Function to Determine Camera Command ---
get_camera_command() {
    # Check for the newest command (Bookworm/Trixie and later)
    if command -v rpicam-still &> /dev/null; then
        echo "rpicam-still"
    # Check for the intermediate command (Bullseye)
    elif command -v libcamera-still &> /dev/null; then
        echo "libcamera-still"
    # Fallback to the old command (Buster/Legacy)
    elif command -v raspistill &> /dev/null; then
        echo "raspistill"
    else
        echo "" # No camera command found
    fi
}

# --- Script Logic ---
CAMERA_CMD=$(get_camera_command)

if [[ -z "$CAMERA_CMD" ]]; then
    echo "Error: Neither rpicam-still, libcamera-still, nor raspistill command was found."
    exit 1
fi

TODAY=$(date +%Y%m%d)
PIC_PATH="$PIC_DIR$TODAY"

if [ ! -d "$PIC_PATH" ]; then
    mkdir -p "$PIC_PATH"
fi
cd "$PIC_PATH"

HMS=$(date +"_%H%M%S")
OUTPUT_FILE="$PIC_PATH/$TODAY$HMS.jpg"

# If it is night time, change the metering from average to spot in an effort to reduce the effects
# of bright lights in the frame.  Also, CAM_TIME (micro-seconds) is the amount of time that the camera software will
# allow the auto exposure algorithm to converge.  At night, since the exposures are very long the algorithm 
# takes a long time to converge.METERING='average'
METERING='average'
CAM_TIME=20000
DAY_OR_NIGHT=$(/home/pi/bin/sunwait poll "$LATITUDE" "$LONGITUDE")
if [ "$DAY_OR_NIGHT" == "NIGHT" ]; then
	METERING='spot'
	CAM_TIME=240000
fi

# --- Execute Camera Command ---
if [ "$CAMERA_CMD" = "raspistill" ]; then
	# For older versions of R Pi OS up to Buster (Legacy stack)
	"$CAMERA_CMD" -o "$OUTPUT_FILE" -a 12 -a "%Y-%m-%d %X %Z" -ae 128 -q 30 -rot "$CAMERA_ROTATION" -ex verylong -t "$CAM_TIME" --metering "$METERING"
else
	# For R Pi OS Bullseye, Bookworm, Trixie and beyond (Libcamera stack)

	# Check memory size for different Pi models (Pi 0 vs others)
	memsize=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
	
	# Set point size based on memory/resolution
	if (($memsize > 524288)); then
		# Pi 2, 3, 4, 5, etc. - Full resolution (default is ~4056x3040)
		POINT_SIZE='100'
		COMMON_OPTS="--tuning-file /home/pi/bin/imx477.json --framerate 0 -o $OUTPUT_FILE --metering $METERING --exposure long -q 30 -t $CAM_TIME --post-process-file /home/pi/bin/drc.json"
	else
		# Pi 0, Pi 1 - Reduced resolution (2028x1520)
		POINT_SIZE='50'
		# NOTE: Removed --post-process-file and added --width/--height on small PIs to save memory
		COMMON_OPTS="--tuning-file /home/pi/bin/imx477.json --framerate 0 -o $OUTPUT_FILE --metering $METERING --exposure long -q 30 -t $CAM_TIME --width 2028 --height 1520"
	fi
	
	# Capture the image
	timeout -s 2 320s "$CAMERA_CMD" $COMMON_OPTS

	# Post-processing (common for libcamera commands)
	# Rotation
	mogrify -rotate "$CAMERA_ROTATION" "$OUTPUT_FILE"
	
	# Timestamping (Uses the calculated POINT_SIZE)
	mogrify -pointsize "$POINT_SIZE" -fill white -undercolor '#00000080' -gravity North -annotate +0+5 "`date`" "$OUTPUT_FILE"
	
	# Thumbnail generation
	convert "$OUTPUT_FILE" -thumbnail '160x120>' temp_thumbnail.jpg
	exiftool -overwrite_original "-ThumbnailImage<=temp_thumbnail.jpg" "$OUTPUT_FILE"
	rm temp_thumbnail.jpg
fi
