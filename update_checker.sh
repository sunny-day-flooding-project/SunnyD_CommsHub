#!/bin/bash 
#
# update_checker.sh is a script that will check for scripts to be run on all gateways.
# It will do the following:
#    check for a file named all_gateways_*.sh
#    run it if all_gateways_*_HOSTNAME.log does not exist (with * being the same)
#    create the log file from the run

# Make a list of all_gateways_*.sh files.
# For each file in list test for log.
#set -x

shopt -s nullglob
cd /home/pi/ALL_GATEWAYS
for f in all_gateways_*.sh
do 
    echo "Processing $f ..."
    lf=`basename "$f" .sh`
    lf="${lf}_`hostname`.log"
    echo "Looking for $lf"
    if [ -f "$lf" ]
    then
        echo "Found $lf, exiting"
    else
        echo "Did not find $lf"
        echo "Running script $f"
	/bin/bash $f > $lf 2>&1
    fi
done
