#!/bin/bash
#
# site-enable.sh is a script that will enable data collection and image collection
#

pushd /home/pi/bin > /dev/null

# Enable/disable data collection
if [ -f dataHandler.sh ]; then
	echo 
	echo Data collection is currently enabled.
	read -n 1 -p "Would you like to disable [y,N]: " doThisSection
	echo
	doThisSection=${doThisSection:-"n"}
	if [ "$doThisSection" == "y" ]; then
		mv dataHandler.sh dataHandler.sh.off
		sudo pkill -9 -o -f dataHandler.py 
	fi

elif [ -f dataHandler.sh.off ]; then
	echo 
	echo Data collection is currently disabled.
	read -n 1 -p "Would you like to enable [y,N]: " doThisSection
	echo
	doThisSection=${doThisSection:-"n"}
	if [ "$doThisSection" == "y" ]; then
		mv dataHandler.sh.off dataHandler.sh
		setsid dataHandler.sh &> /dev/null &
	fi
fi


# Enable/disable logging to cloud database
DB_URL=`confget -f /home/pi/bin/config.ini DB_URL`

if [[ $DB_URL == "no"* ]]; then
	echo 
	echo Logging data to the cloud is currently disabled.
	read -n 1 -p "Would you like to enable [y,N]: " doThisSection
	echo
	doThisSection=${doThisSection:-"n"}
	if [ "$doThisSection" == "y" ]; then
		sed -i -e "s/^#\(.*DB_URL.*=.*\)/\1/" \
			   -e "s/^[^#].*DB_URL.*=.*no.*/#&/"  config.ini
	fi
else
	echo 
	echo Logging data to the cloud is currently enabled.
	read -n 1 -p "Would you like to disable [y,N]: " doThisSection
	echo
	doThisSection=${doThisSection:-"n"}
	if [ "$doThisSection" == "y" ]; then
		sed -i -e "s/^[^#].*DB_URL.*=.*/#&/" \
			   -e "s/^#\(.*DB_URL.*=.*no.*\)/\1/"  config.ini
	fi
fi


# Enable/disable image collection
if [ -f webcam.sh ]; then
	echo 
	echo Image collection is currently enabled.
	read -n 1 -p "Would you like to disable [y,N]: " doThisSection
	echo
	doThisSection=${doThisSection:-"n"}
	if [ "$doThisSection" == "y" ]; then
		mv webcam.sh webcam.sh.off
	fi

elif [ -f webcam.sh.off ]; then
	echo 
	echo Image collection is currently disabled.
	read -n 1 -p "Would you like to enable [y,N]: " doThisSection
	echo
	doThisSection=${doThisSection:-"n"}
	if [ "$doThisSection" == "y" ]; then
		mv webcam.sh.off webcam.sh
	fi
fi


# Enable/disable sending images to the cloud
if [ -f images2api.sh ]; then
	echo 
	echo Sending images to the cloud database is currently enabled.
	read -n 1 -p "Would you like to disable [y,N]: " doThisSection
	echo
	doThisSection=${doThisSection:-"n"}
	if [ "$doThisSection" == "y" ]; then
		mv images2api.sh images2api.sh.off
	fi

elif [ -f images2api.sh.off ]; then
	echo 
	echo Sending images to the cloud database is currently disabled.
	read -n 1 -p "Would you like to enable [y,N]: " doThisSection
	echo
	doThisSection=${doThisSection:-"n"}
	if [ "$doThisSection" == "y" ]; then
		mv images2api.sh.off images2api.sh
	fi
fi


popd > /dev/null
