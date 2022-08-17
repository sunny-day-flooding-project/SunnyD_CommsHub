#!/bin/bash


PIC_DIR="/home/pi/webcam/"

TODAY=`date +%Y%m%d`
if [ ! -d "$PIC_DIR$TODAY" ]; then
    mkdir "$PIC_DIR$TODAY"
fi
cd "$PIC_DIR$TODAY"

HM=$(date +"_%H%M")

if ! command -v libcamera-still &> /dev/null; then
	# For older versions of R Pi OS up to Buster
	raspistill -o $PIC_DIR$TODAY/$TODAY$HM.jpg -a 12 -a "%Y-%m-%d %X %Z" -ae 128 -q 30 -rot 270 -ex verylong -t 20000
else
	# For R Pi OS Bullseye and beyond
	timeout -s 2 60s libcamera-still --tuning-file /home/pi/bin/imx477.json --framerate 0 -o $PIC_DIR$TODAY/$TODAY$HM.jpg --metering average --exposure long -q 30 -t 20000 --post-process-file /home/pi/bin/drc.json
	mogrify -rotate 270 $PIC_DIR$TODAY/$TODAY$HM.jpg
	mogrify -pointsize 100 -fill white -undercolor '#00000080' -gravity North -annotate +0+5 "`date`" $PIC_DIR$TODAY/$TODAY$HM.jpg
fi
