# This was excerpted from dataHandler.py on 4/27/21 to re-write
# all data from DAYS_AGO (below) to the database from the data files.  This is useful 
# for times when some data did not go into the database for unforeseen
# reasons.  Duplicate entries should be ignored by the database.
#
# Modified 8/18/22 to accept a directory name and optional config file name.
# This is useful when updating files that were from some other gateway than the
# one being used to run this program.  (I.E. retrieved a sensor with files that were not uploaded)
#
# Suggested use: Copy the files to be uploaded to their own directory somewhere.
#                Copy the config file from the machine they came from to the same directory
#                Set the days_ago variable below if necessary, otherwise leave it big
#                run
#
#   "Usage " + sys.argv[0] + " fileDirectory optionalConfigFile"
#   if config file is omitted, uses default config file in ~/bin
#
# Tony Whipple
#

# Set this to the number of days before now to start pushing data
DAYS_AGO = 365

import signal
import sys
import requests
import urllib
import glob
from datetime import datetime
from datetime import timedelta
from configobj import ConfigObj

# establish the timedelta to add to the observations
# TD = timedelta(0)
TD = datetime(2024, 7, 28, 7, 41, 35) - datetime(2000, 1, 5, 18, 26, 27)

# if we catch a signal from the OS, clean up and exit
def signal_handler(sig, frame):
    print('Intercepted a signal - Stopping!', flush=True)
    sys.exit(0)
    
# Class to contain the OLA data.  Attempts to parse the data.
# If parsing fails, self.inString will be set to empty    
class OLAdata:
    def __init__(self, inData):
        self.obsNum=-999
        if inData=='':
            self.inString=''
        else:
            # Parse the incoming data into vars if it looks like data
            self.inString = inData.decode()
            self.parseData()

    # If the inData look like real data populate the variables
    # otherwise leave them uninitialized.    

#   This version of parseData is for the Bar02 sensor
    def parseData(self):
        l = self.inString.split(',')
        if len(l)==11:     # num elements+1, split makes a token out of the trailing crlf
            # If any exception, clear the input.  If it was a bad transmission
            # the check sequential step should catch it.
            try:
                self.obsDateTime = datetime.strptime(l[0]+' '+l[1], "%m/%d/%Y %H:%M:%S.%f")
                self.battVolts = float(l[2])
                self.aX = float(l[3])
                self.aY = float(l[4])
                self.aZ = float(l[5])
                self.temp = float(l[6])
                self.press = float(l[7])
                self.wtemp = float(l[8])
                self.obsNum = int(l[9])
                #print(vars(self))
            except:
                self.inString = ''# Clear inString if this fails parsing
        else:
            self.inString = ''    # Clear inString if this fails parsing
            


# write the observation to the cloud database
def write_database(newData):
    # database access is through http "post" for example:
    # https://api-sunnydayflood.cloudapps.unc.edu/write_water_level?key=jjRa6S550zvTxMF&place=Carolina%20Beach
    #%2C%20North%20Carolina&sensor_id=CB_02&dttm=20210223050000&level=-.25&voltage=4.8&notes=test 
    #
    numTries=0  #number of tries to post
    MAX_TRIES = 2
    db_url = config['dataHandler']['DB_URL'] + "/write_measurement"

    post_data = { 
                  'place':config['dataHandler']['PLACE'],
                  'sensor_ID':config['dataHandler']['SITE_ID'],
                  'date':newData.obsDateTime.astimezone().isoformat(),

                  # Calibrate pressure value while writing to database
                  'raw_pressure':newData.press,
                  'pressure':newData.press - float(config['dataHandler']['SENSOR_OFFSET']) - (float(config['dataHandler']['SENSOR_TEMP_FACTOR']) * newData.wtemp),
                  'voltage':newData.battVolts,
                  'seqNum':newData.obsNum,
                  'aX':newData.aX,
                  'aY':newData.aY,
                  'aZ':newData.aZ,
                  'wtemp':newData.wtemp,
                  'notes':" " }

    while numTries < MAX_TRIES:
        try:
            r=requests.post(url=db_url, json=post_data, timeout=10, auth=(config['dataHandler']['API_USER'], config['dataHandler']['API_PASS']))
            r.raise_for_status()    # throw an exception if the status is bad
            success = True
            break
        except Exception as ex:
            template = "An exception of type {0} occurred. Arguments:\n{1!r}"
            message = template.format(type(ex).__name__, ex.args)
            print(message)
            # In order to resync the database, check to see if the next sequence number is in the data files,
            # if so try to put it in after the next observation.  If not, we might need to get the data files
            # and use date to keep up-to-date
            print("Exception posting to database.  Database out of sync.")
            success = False
            numTries = numTries + 1
            if numTries < MAX_TRIES:
                print("Trying to post another time")
        
    return success


# If we recently downloaded data files and need to re-sync the data, we will
# read through the data files to re-sync.
def update_db_from_data_files():
    success = False
    # This is a modification of update_db_from_logged_files.
    #
    # get the last entry in the db
    # check to see if we have the next sequence number in the data files
    # if so, write it to the db.  Do this until caught up
    prevData = OLAdata('')    
    print("Attempting to catch database up from ALL data files past the following date:")
    lastDate = datetime.today() - timedelta( days=DAYS_AGO )     # within the last n days
    print(lastDate)

    # get a list of data files - since the dates in them are unknown, have to open them all
    flist = glob.glob(updateFileDir+'/dataLog?????.TXT')
    flist.sort()   # sort the file list ascending
    for fn in flist:
        # open the file and look for the first date that is greater
        # ignoring seqNum going by date only. insert it and loop to end
        # if not, we tried, we failed.  Will have to try again
        f = open(fn, "rt")
        for fline in f:
            fdata = OLAdata(fline.encode("ascii", "ignore"))
            if fdata.inString != '':    # if the line fails parsing we will skip it.
                # add the timedelta to fData
                fdata.obsDateTime = fdata.obsDateTime + TD
    
                if fdata.obsDateTime > lastDate:
                    if write_database(fdata) == True:
                        print('Successfully wrote: ', end='')
                        print(fdata.obsDateTime.strftime('%m/%d/%Y,%H:%M:%S'), end='')
                        print(fdata.inString[22:], end='', flush=True)
                        lastDate = fdata.obsDateTime
                        prevData = fdata
                        success = True
                    else:
                        success = False
                        f.close()
                        print("\nWrite database failed.  Failed attempt to catch database up from downloaded data files.")
                        return prevData   # if we fail, get out and try again later
                else:
                    success = False
        f.close()
            
    if success == True:
        print("\nSuccessfully caught database up using downloaded data files.")
    else:
        print("\nFailed attempt to catch database up from downloaded data files.")
    return prevData

def main():
    update_db_from_data_files()

if __name__ == "__main__":
    if len(sys.argv) == 1:
        print("NOTE: In this version the time delta needs to be manually edited in the source code!\n")
        print("Usage " + sys.argv[0] + " fileDirectory optionalConfigFile")
        print("Looks in fileDirectory for files matching dataLog?????.TXT")
        print("  if config file is omitted, uses default config file in ~/bin")
        exit()
    if len(sys.argv) > 1:
        updateFileDir = sys.argv[1]
    if len(sys.argv) > 2:
        config = ConfigObj(sys.argv[2])
    else:
        config = ConfigObj("/home/pi/bin/config.ini")  # Read the config file (current directory)
    
    # catch some signals and perform an orderly shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGHUP, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGQUIT, signal_handler)
    signal.signal(signal.SIGILL, signal_handler)
    signal.signal(signal.SIGABRT, signal_handler)
    signal.signal(signal.SIGFPE, signal_handler)
    signal.signal(signal.SIGSEGV, signal_handler)
    
    main()
    