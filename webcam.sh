#!/bin/bash
set -x

PIC_DIR="/home/pi/webcam/"

LATITUDE=`confget -f /home/pi/bin/config.ini LATITUDE`
if [[ -z "$LATITUDE" ]]
then
	LATITUDE='35N'
fi

LONGITUDE=`confget -f /home/pi/bin/config.ini LONGITUDE`
if [[ -z "$LONGITUDE" ]]
then
	LONGITUDE='77W'
fi

CAMERA_ROTATION=`confget -f /home/pi/bin/config.ini CAMERA_ROTATION`
if [[ -z "$CAMERA_ROTATION" ]]
then
	CAMERA_ROTATION='0'
fi

TODAY=`date +%Y%m%d`
if [ ! -d "$PIC_DIR$TODAY" ]; then
    mkdir "$PIC_DIR$TODAY"
fi
cd "$PIC_DIR$TODAY"

HMS=$(date +"_%H%M%S")

# If it is night time, change the metering from average to spot in an effort to reduce the effects
# of bright lights in the frame.  Also, CAM_TIME (micro-seconds) is the amount of time that the camera software will
# allow the auto exposure algorithm to converge.  At night, since the exposures are very long the algorithm 
# takes a long time to converge.
METERING='average'
CAM_TIME=20000
DAY_OR_NIGHT=`/home/pi/bin/sunwait poll $LATITUDE $LONGITUDE`
if [ "$DAY_OR_NIGHT" == "NIGHT" ]; then
	METERING='spot'
	CAM_TIME=240000
fi

if ! command -v libcamera-still &> /dev/null; then
	# For older versions of R Pi OS up to Buster
	raspistill -o $PIC_DIR$TODAY/$TODAY$HMS.jpg -a 12 -a "%Y-%m-%d %X %Z" -ae 128 -q 30 -rot $CAMERA_ROTATION -ex verylong -t $CAM_TIME --metering $METERING
else
	# For R Pi OS Bullseye and beyond
	memsize=$(cat /proc/meminfo | grep MemTotal | awk '{print $2 }')
	# if we have (less than) 512k (probably a pi 0) must reduce image requirements
	if (($memsize > 524288)); then
		timeout -s 2 320s libcamera-still --tuning-file /home/pi/bin/imx477.json --framerate 0 -o $PIC_DIR$TODAY/$TODAY$HMS.jpg --metering $METERING --exposure long -q 30 -t $CAM_TIME --post-process-file /home/pi/bin/drc.json
		mogrify -rotate $CAMERA_ROTATION $PIC_DIR$TODAY/$TODAY$HMS.jpg
		mogrify -pointsize 100 -fill white -undercolor '#00000080' -gravity North -annotate +0+5 "`date`" $PIC_DIR$TODAY/$TODAY$HMS.jpg
	else
		timeout -s 2 320s libcamera-still --tuning-file /home/pi/bin/imx477.json --framerate 0 -o $PIC_DIR$TODAY/$TODAY$HMS.jpg --metering $METERING --exposure long -q 30 -t $CAM_TIME --width 2028 --height 1520
		mogrify -rotate $CAMERA_ROTATION $PIC_DIR$TODAY/$TODAY$HMS.jpg
		mogrify -pointsize 50 -fill white -undercolor '#00000080' -gravity North -annotate +0+5 "`date`" $PIC_DIR$TODAY/$TODAY$HMS.jpg
	fi
fi

