#!/bin/bash
set -x

PIC_DIR="/mnt/nas/SunnyD/SunnyD01/webcam/"

#YESTERDAY=`date --date="-1 day" +%Y%m%d`
#TODAY=`date +%Y%m%d`
#
#if [ ! -d "$PIC_DIR$YESTERDAY" ]; then
#    mkdir "$PIC_DIR$YESTERDAY"
#fi
#cd "$PIC_DIR$YESTERDAY"

timeout -s 2 119s lftp sftp://sunnyd:SunnyD6841@wave.ims.unc.edu -e "mirror -R -c -v /home/pi/webcam/ $PIC_DIR; bye"


