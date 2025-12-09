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

#
# functions
#
create_wifi_connection() {
	# --- Check OS Version ---
	if [[ -f /etc/os-release ]]; then
		. /etc/os-release
		# If VERSION_CODENAME is lexically less than 'trixie'
		declare -A DEBIAN_ORDER=([buster]=10 [bullseye]=11 [bookworm]=12 [trixie]=13 [forky]=14)
		CURRENT=${DEBIAN_ORDER[$VERSION_CODENAME]:-0}
		if (( CURRENT < 13 )); then
			echo "Detected: $PRETTY_NAME"
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
		else
			echo "✅ OS check detected: $PRETTY_NAME"

			# --- Prompt for Wi-Fi details ---
			read -rp "Enter SSID: " SSID

			# --- Define connection path ---
			CONN_DIR="/etc/NetworkManager/system-connections"
			CONN_FILE="$CONN_DIR/${SSID// /_}.nmconnection"

			# --- Check for existing connection ---
			if nmcli -t -f NAME connection show | grep -Fxq "$SSID"; then
				echo "Connection '$SSID' already exists."
				read -rp "Would you like to replace it? [y/N]: " REPLACE
				if [[ "$REPLACE" =~ ^[Yy]$ ]]; then
					echo "Removing existing connection..."
					nmcli connection delete "$SSID" || true
					rm -f "$CONN_FILE" || true
				else
					echo "Aborting — existing connection kept."
					return
				fi
			fi

			echo Passwords will be encrypted for storage
			echo If the password is less than 8 characters or more than 63 it will have to be entered manually.
			read -rsp "Enter Wi-Fi Password: " PASSWORD
			echo
			echo Priority values are small integers, higher numbers are higher priority.
			echo Use 9 for top priority like cell-phone hotspots etc.
			echo Use 5 normal connections
			echo Use other numbers to raise or lower this connections priority.
			read -rp "Enter priority (higher number = higher priority): " PRIORITY

			# --- Generate hashed PSK ---
			HASHED_PSK=$(wpa_passphrase "$SSID" "$PASSWORD" | grep '^\s*psk=' | tail -n1 | cut -d= -f2)

			if [[ -z "$HASHED_PSK" ]]; then
				echo "❌ Failed to generate PSK. Check your inputs."
				return
			fi

			# --- Create the .nmconnection file ---
			bash -c "cat > '$CONN_FILE' <<EOF
[connection]
id=$SSID
uuid=$(uuidgen)
type=802-11-wireless
autoconnect=true
autoconnect-priority=$PRIORITY
permissions=

[wifi]
mode=infrastructure
ssid=$SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$HASHED_PSK

[ipv4]
method=auto

[ipv6]
addr-gen-mode=default
method=auto
EOF"

			# --- Secure permissions ---
			chmod 600 "$CONN_FILE"

			echo "✅ Created/updated secure connection file:"
			echo "   $CONN_FILE"

			echo "Reloading NetworkManager..."
			nmcli connection reload

			echo "✅ Connection '$SSID' created with priority $PRIORITY."
			
		fi
	else
		echo "❌ Unable to determine OS version (missing /etc/os-release)."
		return
	fi
	return
}



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
	
	# run the function
	create_wifi_connection	
	
    popd > /dev/null
fi

echo
read -n 1 -p "Would you like to set up the UPS hardware (only needs to be done once)? [y,N]: " doThisSection
echo
doThisSection=${doThisSection:-"n"}
if [ "$doThisSection" == "y" ]; then
    lifepo4wered-cli set AUTO_BOOT 3
    lifepo4wered-cli set AUTO_SHDN_TIME 60
	lifepo4wered-cli set WATCHDOG_GRACE 600
	lifepo4wered-cli set WATCHDOG_TIMER 600
	lifepo4wered-cli set WATCHDOG_CFG 2
    lifepo4wered-cli set CFG_WRITE 0x46
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
	chmod +x /home/pi/bin/*.sh /home/pi/bin/*.sh.off /home/pi/bin/sunwait
    
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
	read -p "Enter alert message email addresses (semi-colon separated): " alertRecip
	echo "Lat/Lon can be approximate and are used to determine sunrise and sunset times."
	echo "Enter in floating-point degrees, with [NESW] appended."
	read -p "Enter approximate site latitude: " siteLat
	read -p "Enter approximate site longitude: " siteLon
	read -p "Enter camera rotation in degrees: " camRot
    read -p "Enter sensor calibration offset: " sensorOffset
    read -p "Enter sensor temperature factor: " tempFactor
    read -p "Enter API password: " APIpass
    
    sed -e s/PLACE.*=.*/"PLACE = '$placeName'"/ \
        -e s/SITE_ID.*=.*/"SITE_ID = $siteID"/ \
        -e s/CAMERA_ID.*=.*/"CAMERA_ID = $cameraID"/ \
        -e s/ALERT_RECIPIENTS.*=.*/"ALERT_RECIPIENTS = $alertRecip"/ \
        -e s/LATITUDE.*=.*/"LATITUDE = $siteLat"/ \
        -e s/LONGITUDE.*=.*/"LONGITUDE = $siteLon"/ \
		-e s/CAMERA_ROTATION.*=.*/"CAMERA_ROTATION = $camRot"/ \
        -e s/SENSOR_OFFSET.*=.*/"SENSOR_OFFSET = $sensorOffset"/ \
        -e s/SENSOR_TEMP_FACTOR.*=.*/"SENSOR_TEMP_FACTOR = $tempFactor"/ \
        -e s/API_PASS.*=.*/"API_PASS = $APIpass"/ \
        < config.ini > tmp.tmp
    su pi -c 'cp tmp.tmp config.ini'
	rm tmp.tmp
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
read -n 1 -p "Would you like to remove the current VNC ID (this will disconnect and render a remote session impossible) [y,N]: " doThisSection
echo
doThisSection=${doThisSection:-"n"}
if [ "$doThisSection" == "y" ]; then
	echo "Stopping VNC service..."
	systemctl stop vncserver-x11-serviced

	echo "Removing VNC identity (Cloud ID & keys)..."
	rm -rf /root/.vnc

	echo "Starting VNC service..."
	systemctl start vncserver-x11-serviced

	echo "Identity removed"
	echo "Reconnect through the user interface."
fi


echo
echo Dont forget to restart the system if you changed the host name!
echo Also, an initial survey and initial observations need to be written to the
echo database before sending data.
echo https://api-sunnydayflood.apps.cloudapps.unc.edu/docs#/ for write_survey and write_measurement
echo https://photos-sunnydayflood.apps.cloudapps.unc.edu/docs#/ for write_camera and upload_picture
echo
read -p "Press enter to continue..."

