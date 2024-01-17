#!/bin/bash 
#
# site-update.sh is a script that will set up a gateway for operation at a specific site.
# It will do the following:
#	change the system name to GWXX
#	set up UPS hardware
#	install local updates from GIT
#	add the BLE address to autoconnect.ini
#	populate config.ini
#	add wifi information
#

echo 
echo 'Information necessary to complete the site setup:'
echo '   New hostname (gateway number) for this system (ex. GW99)'
echo '   BLE address of the sensor to be associated with this gateway'
echo '   Config information:'
echo '      Place Name'
echo '      Site ID'
echo '      Camera ID'
echo '      Sensor calibration offset'
echo '      Sensor calibration temperature factor'
echo '      API password'
echo 
echo 'This script can be run multiple times and values not set will remain as they were.'
echo

# This script must be run as root.  Check to see if we are.
iam=`whoami`
if [ "$iam" != "root" ]; then
    echo This script must be run as root.  Sorry $iam.
    exit 1
fi

echo
echo The software update step in this script requires a working internet connection.
echo
read -n 1 -p "Would you like to add wifi information? [y,N]: " doThisSection
echo
doThisSection=${doThisSection:-"n"}
if [ "$doThisSection" == "y" ]; then
    pushd /etc/wpa_supplicant > /dev/null

    echo
    echo If there are spaces in the SSID or password, put them in quotes.
    echo If the password is less than 8 characters or more than 63 it will have to be entered manually.
    echo
	read -p "Enter the SSID: " wifiSSID
	echo Passwords will be encrypted for storage
	read -p "Enter the password: " wifiPass
	echo
	echo Priority values are small integers, higher numbers are higher priority.
	echo Use 9 for top priority like cell-phone hotspots etc.
	echo Use 5 normal connections
	echo Use other numbers to raise or lower this connections priority.
	read -p "Enter priority: " wifiPriority
    
	echo >> wpa_supplicant.conf
	wpa_passphrase $wifiSSID $wifiPass | grep -v "#psk" >> wpa_supplicant.conf
	sed -i s/ssid=\"$wifiSSID\"/ssid=\"$wifiSSID\"\\n\\tpriority=$wifiPriority/ wpa_supplicant.conf
	
    popd > /dev/null
fi

echo
read -n 1 -p "Would you like to change the hostname? [y,N]: " doThisSection
echo
doThisSection=${doThisSection:-"n"}
if [ "$doThisSection" == "y" ]; then

    # change the site name
    read -p "Enter the new gateway/host name (ex. GW99): " NEW_SITE_NAME
    echo
    echo This gateway will be set to \"$NEW_SITE_NAME\".

    read -n 1 -p "Continue? [y,N] " toContinue
    toContinue=${toContinue:-"n"}
    if [ "$toContinue" != "y" ]; then
        echo "Exiting script"
        exit 1
    fi
    echo

    OLD_SITE_NAME=`hostname`    # save the current name of this box
    echo Changing hostname in files /etc/hostname and /etc/hosts from $OLD_SITE_NAME to $NEW_SITE_NAME

    echo $NEW_SITE_NAME > /etc/hostname
    hostname $NEW_SITE_NAME

    # Put in temp file and display with y/n option in case of substitution errors
    sed s/$OLD_SITE_NAME/$NEW_SITE_NAME/g < /etc/hosts > /home/pi/bin/hosts.tmp
    echo
    echo Check that there were no substitution errors.
    echo
    cat /home/pi/bin/hosts.tmp
    echo
    read -n 1 -p "Does this look correct? [y,N] " isCorrect
    echo
    isCorrect=${isCorrect:-"n"}
    if [ "$isCorrect" != "y" ]; then
        echo Leaving this version as /home/pi/bin/hosts.tmp - not modifying original
        echo Edit original correctly or re-run script when this finishes.
    else
        cp /home/pi/bin/hosts.tmp /etc/hosts
        rm /home/pi/bin/hosts.tmp
        echo NOTE that the name change wont take effect until reboot.
    fi
fi

echo
read -n 1 -p "Would you like to set up the UPS hardware (only needs to be done once)? [y,N]: " doThisSection
echo
doThisSection=${doThisSection:-"n"}
if [ "$doThisSection" == "y" ]; then
    lifepo4wered-cli set auto_boot 3
    lifepo4wered-cli set auto_shdn_time 60
    lifepo4wered-cli set cfg_write 0x46
    echo Done.
fi

echo
echo This step requires a working internet connection.
read -n 1 -p "Would you like to update gateway software from the GIT repository? [y,N]: " doThisSection
echo
doThisSection=${doThisSection:-"n"}
if [ "$doThisSection" == "y" ]; then
	echo
    echo Be careful overwriting config.ini if values have already be edited/entered.
    pushd /home/pi/SunnyD_CommsHub > /dev/null
    su pi -c 'git pull'
    # if a '.off' version exists in bin, rename this version '.off' as well
	if ls /home/pi/bin/*.off 1> /dev/null 2>&1; then
		for f in /home/pi/bin/*.off
		do
			mv $(basename $f .off) $(basename $f .off).off
		done
	fi
    
	echo
	echo If not already up to date answer y for files that you want to copy to bin, overwriting the existing versions.
	echo
    su pi -c "cp --update --interactive *.sh *.ini *.py *.json sunwait /home/pi/bin/"
	cp --update --interactive rc.local msmtprc /etc/
    # copy, then strip off any '.off' extensions if they exist
	if ls *.off 1> /dev/null 2>&1; then
        su pi -c "cp --update --interactive *.off /home/pi/bin/"
		for f in *.off
		do
			mv $f $(basename $f .off)
		done
	fi
    
    popd > /dev/null
fi

echo
read -n 1 -p "Would you like to add a BLE address to autoconnect? [y,N]: " doThisSection
echo
doThisSection=${doThisSection:-"n"}
if [ "$doThisSection" == "y" ]; then
    pushd /home/pi/bin > /dev/null
    
    while
        echo Be careful not to duplicate entries as they are not allowed.
        read -p "Enter the BLE address in hex separated by colons (e.g. FF:FF:...): " newBLE
        echo
        echo You entered $newBLE
        read -n 1 -p "Is this correct? [y,N]: " isCorrect
        [ "$isCorrect" != "y" ]
    do
        continue
    done
    
    echo "
[$newBLE]
dev = $newBLE
read-uuid = 6e400003-b5a3-f393-e0a9-e50e24dcca9e 
write-uuid = 6e400002-b5a3-f393-e0a9-e50e24dcca9e
"    >> /home/pi/bin/autoconnect.ini

    # now restart the process that uses them
    pkill -f "python3 /home/pi/bin/ble-autoconnect.py -c /home/pi/bin/autoconnect.ini"
    su pi -c '/home/pi/bin/run_ble_serial.sh' > /dev/null &
    popd > /dev/null
fi

echo
read -n 1 -p "Would you like to enter config values? [y,N]: " doThisSection
echo
doThisSection=${doThisSection:-"n"}
if [ "$doThisSection" == "y" ]; then
    pushd /home/pi/bin > /dev/null

    read -p "Enter PLACE name: " placeName
    read -p "Enter SITE ID: " siteID
    read -p "Enter CAMERA ID: " cameraID
    read -p "Enter sensor calibration offset: " sensorOffset
    read -p "Enter sensor temperature factor: " tempFactor
    read -p "Enter API password: " APIpass
    
    sed -e s/PLACE.*=.*/"PLACE = '$placeName'"/ \
        -e s/SITE_ID.*=.*/"SITE_ID = $siteID"/ \
        -e s/CAMERA_ID.*=.*/"CAMERA_ID = $cameraID"/ \
        -e s/SENSOR_OFFSET.*=.*/"SENSOR_OFFSET = $sensorOffset"/ \
        -e s/SENSOR_TEMP_FACTOR.*=.*/"SENSOR_TEMP_FACTOR = $tempFactor"/ \
        -e s/API_PASS.*=.*/"API_PASS = $APIpass"/ \
        < config.ini > tmp.tmp
    su pi -c 'cp tmp.tmp config.ini'
	rm tmp.tmp
    popd > /dev/null
fi

echo
echo Dont forget to restart the system if you changed the host name!
echo
