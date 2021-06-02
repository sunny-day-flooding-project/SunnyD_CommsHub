#!/bin/bash


PIC_DIR="/home/pi/webcam/"

TODAY=`date +%Y%m%d`
if [ ! -d "$PIC_DIR$TODAY" ]; then
    mkdir "$PIC_DIR$TODAY"
fi
cd "$PIC_DIR$TODAY"

HM=$(date +"_%H%M")

raspistill -o $PIC_DIR$TODAY/$TODAY$HM.jpg -a 12 -a "%Y-%m-%d %X %Z" -ae 128 -q 30 -rot 270 -ex verylong -t 20000

