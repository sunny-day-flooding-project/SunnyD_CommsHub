#!/bin/bash
#set -x

if pidof -o %PPID -x "images2api.sh">/dev/null; then
	echo "Process already running"
	exit 1
fi

# API_KEY is no longer necessary
#API_KEY=`cfget --cfg /home/pi/bin/config.ini dataHandler/API_KEY`
#if [[ -z "$API_KEY" ]]
#then
#    echo $'Did not find config value API_KEY.  Exiting\n'
#    exit 1
#fi

API_USER=`cfget --cfg /home/pi/bin/config.ini dataHandler/API_USER`
if [[ -z "$API_USER" ]]
then
    echo $'Did not find config value API_USER.  Exiting\n'
    exit 1
fi

API_PASS=`cfget --cfg /home/pi/bin/config.ini dataHandler/API_PASS`
if [[ -z "$API_PASS" ]]
then
    echo $'Did not find config value API_PASS.  Exiting\n'
    exit 1
fi

CAMERA_ID=`cfget --cfg /home/pi/bin/config.ini dataHandler/CAMERA_ID`
if [[ -z "$CAMERA_ID" ]]
then
    echo $'Did not find config value CAMERA_ID.  Exiting\n'
    exit 1
fi

PIC_DIR_BASE='/home/pi/webcam'
cd $PIC_DIR_BASE

shopt -s nullglob
PIC_DIRS=(20*/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
#echo "${PIC_DIRS[@]}"  # Note double-quotes to avoid extra parsing of funny characters in filenames

echo "Retrieving latest picture info from data base."

# API call pre March 2022
#LATEST_DATE=$(curl --progress-bar "https://photos-sunnydayflood.apps.cloudapps.unc.edu/get_latest_picture_info?key=jjRa6S550zvTxMF&camera_ID=$CAMERA_ID" | jq '.[0].DateTimeOriginal')

CO=$(curl --progress-bar \
       	"https://photos-sunnydayflood.apps.cloudapps.unc.edu/get_latest_picture_info?camera_ID=$CAMERA_ID" \
	--basic --user $API_USER:$API_PASS )
echo
echo $CO
echo
LATEST_DATE=$(echo $CO | jq '.[0].DateTimeOriginal')


DATE_NUM=${LATEST_DATE:1:4}${LATEST_DATE:6:2}${LATEST_DATE:9:2}${LATEST_DATE:12:2}${LATEST_DATE:15:2}

echo -n "The latest picture date is: "
echo $DATE_NUM
echo "Sending new files to database."

# For each directory, check if it is equal to or larger than the latest date.
LATEST_YMD=${DATE_NUM:0:8}
for filedir in ${PIC_DIRS[@]}
do
    #echo "is $filedir > $LATEST_YMD?"
    if [ ${filedir:0:8} -ge $LATEST_YMD ]
    then
        #echo Yes
		cd $PIC_DIR_BASE/$filedir
		shopt -s nullglob
		PIC_FILES=(20*.jpg)
		shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later

		# For each file in this directory, check if it is larger than the latest date
		for picfile in ${PIC_FILES[@]}
		do
			pf=${picfile:0:8}${picfile:9:4}
			
			#echo "is $pf > $DATE_NUM?"
			if [ $pf -gt $DATE_NUM ]
			then
				echo $'\nAdding '$pf' to database.'
				# Push the file to the db, bail out if this fails

# API Call pre-March 2022                
#				ret=$(curl --max-time 30 -X POST \
#				"https://photos-sunnydayflood.apps.cloudapps.unc.edu/upload_picture?key=jjRa6S550zvTxMF&camera_ID=$CAMERA_ID&timezone=EST" \
#				-H "accept: */*" -H "Content-Type: multipart/form-data" -F "file=@$picfile;type=image/jpeg")

				ret=$(curl --max-time 30 -X POST \
                    "https://photos-sunnydayflood.apps.cloudapps.unc.edu/upload_picture" \
                    -F "file=@$picfile;type=image/jpeg" \
                    -F "camera_ID=$CAMERA_ID;type=*/*" \
                    -F "timezone=EST;type=*/*" \
                    --basic --user $API_USER:$API_PASS )
                
				status="$?"
				echo -n "Return form curl: "
				echo "$ret"
				echo $'Received code ' $status $' from curl.\n'
				if [[ $ret != *"SUCCESS"* ]]
				then
					echo $'\nCurl did not return SUCCESS.  Exiting\n'
					exit 1
				fi
				if [ $status -ne 0 ]
				then
					echo $'\nReceived error code ' $? $' from curl.  Exiting\n'
					exit 1
				fi
			fi

		done
    fi
done
