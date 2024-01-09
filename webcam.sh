#!/bin/bash
set -x

PIC_DIR="/home/pi/webcam/"

TODAY=`date +%Y%m%d`
if [ ! -d "$PIC_DIR$TODAY" ]; then
    mkdir "$PIC_DIR$TODAY"
fi
cd "$PIC_DIR$TODAY"

HM=$(date +"_%H%M")

# If it is night time, change the metering from average to spot in an effort to reduce the effects
# of bright lights in the frame.  Also, CAM_TIME (micro-seconds) is the amount of time that the camera software will
# allow the auto exposure algorithm to converge.  At night, since the exposures are very long the algorithm 
# takes a long time to converge.
METERING='average'
CAM_TIME=20000
DAY_OR_NIGHT=`/home/pi/bin/sunwait poll 35N 77W`
if [ "$DAY_OR_NIGHT" == "NIGHT" ]; then
	METERING='spot'
	CAM_TIME=240000
fi

if ! command -v libcamera-still &> /dev/null; then
	# For older versions of R Pi OS up to Buster
	raspistill -o $PIC_DIR$TODAY/$TODAY$HM.jpg -a 12 -a "%Y-%m-%d %X %Z" -ae 128 -q 30 -rot 270 -ex verylong -t $CAM_TIME --metering $METERING
else
	# For R Pi OS Bullseye and beyond
	memsize=$(cat /proc/meminfo | grep MemTotal | awk '{print $2 }')
	# if we have (less than) 512k (probably a pi 0) must reduce image requirements
	if (($memsize > 524288)); then
		timeout -s 2 300s libcamera-still --tuning-file /home/pi/bin/imx477.json --framerate 0 -o $PIC_DIR$TODAY/$TODAY$HM.jpg --metering $METERING --exposure long -q 30 -t $CAM_TIME --post-process-file /home/pi/bin/drc.json
		mogrify -rotate 270 $PIC_DIR$TODAY/$TODAY$HM.jpg
		mogrify -pointsize 100 -fill white -undercolor '#00000080' -gravity North -annotate +0+5 "`date`" $PIC_DIR$TODAY/$TODAY$HM.jpg
	else
		timeout -s 2 300s libcamera-still --tuning-file /home/pi/bin/imx477.json --framerate 0 -o $PIC_DIR$TODAY/$TODAY$HM.jpg --metering $METERING --exposure long -q 30 -t $CAM_TIME --width 2028 --height 1520
		#mogrify -rotate 270 $PIC_DIR$TODAY/$TODAY$HM.jpg
		mogrify -pointsize 50 -fill white -undercolor '#00000080' -gravity North -annotate +0+5 "`date`" $PIC_DIR$TODAY/$TODAY$HM.jpg
	fi
fi

