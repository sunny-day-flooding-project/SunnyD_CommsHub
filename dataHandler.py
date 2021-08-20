#
# Data handler
#
# Listens to Bluetooth serial port for incoming lines of data.
# Checks that the data are sequential.
# If not, trigger file catch-up. Also trigger file catch-up upon start.  That way
#  periodic restarts trigger periodic file catch-up.
#     Download files that are either larger or new.
#     Scan the new files and insert new data in the database. (Ordered by date-time
#         since sample number might have reset.)
# Else save to a local file and insert this line in database.
#
# Written March 2021 by Tony Whipple
#

import serial
import pexpect
from pexpect import fdpexpect
import time
import signal
import sys
import requests
import urllib
import os
import glob
from datetime import datetime
from datetime import timedelta
from configobj import ConfigObj

# override print so each statement is timestamped
old_print = print
def timestamped_print(*args, **kwargs):
  old_print(datetime.now(), *args, **kwargs)
print = timestamped_print

# if we catch a signal from the OS, clean up and exit
def signal_handler(sig, frame):
    print('Intercepted a signal - Stopping!', flush=True)
    ser.close()
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
    
#   This version of parseData was for the micro-pressure sensor     
#    def parseData(self):
#        l = self.inString.split(',')
#        if len(l)==10:     # num elements+1, split makes a token out of the trailing crlf
#            # If any exception, clear the input.  If it was a bad transmission
#            # the check sequential step should catch it.
#            try:
#                self.obsDateTime = datetime.strptime(l[0]+' '+l[1], "%m/%d/%Y %H:%M:%S.%f")
#                self.battVolts = float(l[2])
#                self.aX = float(l[3])
#                self.aY = float(l[4])
#                self.aZ = float(l[5])
#                self.temp = float(l[6])
#                self.press = float(l[7])
#                self.obsNum = int(l[8])
#                #print(vars(self))
#            except:
#                self.inString = ''# Clear inString if this fails parsing
#        else:
#            self.inString = ''    # Clear inString if this fails parsing

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
            

# returns true or false whether this value is sequential with the last
def check_sequential(newData, prevData):
    # Check if the new data is sequential with the previous data
    if newData.obsNum == prevData.obsNum+1:
        return True
    else:
        return False

# writes data received through bluetooth to a logged data file (separate from downloaded files)
def write_local_file(newData):
    # write the data to a local file
    
    fn = config['dataHandler']['LOGGED_FILE_DIR']+"/" + datetime.today().strftime('%Y%m%d') + ".txt"
    outfile = open(fn, "a")
    outfile.write(newData.inString)
    outfile.close()


# write the observation to the cloud database
def write_database(newData):
    # database access is through http "post" for example:
    # https://api-sunnydayflood.cloudapps.unc.edu/write_water_level?key=jjRa6S550zvTxMF&place=Carolina%20Beach
    #%2C%20North%20Carolina&sensor_id=CB_02&dttm=20210223050000&level=-.25&voltage=4.8&notes=test 
    #
    db_url = config['dataHandler']['DB_URL'] + "/write_water_level"
#    db_url = config['dataHandler']['DB_URL'] + "/bite_water_level"     # for testing, this makes the write fail
    post_data = { 'key':config['dataHandler']['API_KEY'],
                  'place':config['dataHandler']['PLACE'],
                  'sensor_id':config['dataHandler']['SITE_ID'],
                  'dttm':newData.obsDateTime.strftime('%Y%m%d%H%M%S'),
#                  'pressure':newData.press * 10.0,           # convert kPa to mBar (for the micro-pressure sensor data)

                  # Calibrate pressure value while writing to database
                  'pressure':newData.press - float(config['dataHandler']['SENSOR_OFFSET']) - (float(config['dataHandler']['SENSOR_TEMP_FACTOR']) * newData.wtemp),
                  'voltage':newData.battVolts,
                  'seqNum':newData.obsNum,
                  'aX':newData.aX,
                  'aY':newData.aY,
                  'aZ':newData.aZ,
                  'wtemp':newData.wtemp,
                  'notes':" " }
    xdata = urllib.parse.urlencode(post_data, quote_via=urllib.parse.quote)

    try:
        r=requests.post(url=db_url, params=xdata, timeout=10)
#        print(r.url)
#        print(r.text)
        r.raise_for_status()    # throw an exception if the status is bad
        success = True
    except Exception as ex:
        template = "An exception of type {0} occurred. Arguments:\n{1!r}"
        message = template.format(type(ex).__name__, ex.args)
        print(message)
        # In order to resync the database, check to see if the next sequence number is in the data files,
        # if so try to put it in after the next observation.  If not, we might need to get the data files
        # and use date to keep up-to-date
        print("Exception posting to database.  Database out of sync.")
        success = False
    return success


# If logging to the database got out of sync, we will try reading through the logged data files
# to re-sync.
def update_db_from_logged_files():
    success = False
    one_second = timedelta(seconds=1)
    # get the last entry in the db
    # check to see if we have the next sequence number in the logged files
    # if so, write it to the db.  Do this until seq is one less than newData and set SYNC flac to False
    
    print("Attempting to catch database up from logged files.")
    
    db_url = config['dataHandler']['DB_URL'] + "/latest_water_level"
    get_data = { 'key':config['dataHandler']['API_KEY'],
                 'sensor_id':config['dataHandler']['SITE_ID'] }
    try:
        rd = requests.get(url=db_url, params=get_data)
    except:
        success = False
        return success
        
    print(rd.url)
    print(rd.text)
    j = rd.json()
    lastDate = datetime.strptime(j[0]["date"], "%Y-%m-%d %H:%M:%S")
    UTCtoEST = timedelta(hours=5)
    lastDate = lastDate - UTCtoEST
    print(lastDate)
    lastSeqNum = j[0]["seqNum"]
    # get a list of logged files with this date or greater
    flist = glob.glob(config['dataHandler']['LOGGED_FILE_DIR']+'/20??????.txt')
    flist.sort()   # sort the file list ascending
    for fn in flist:
        try:
            # get the filename prefix and convert to int
            fn_pre = fn.split('/')[-1]
            fn_int = int(os.path.splitext(fn_pre)[0])
        except:
            continue   # if the fn is not an int move on
        if fn_int >= int(datetime.strftime(lastDate, "%Y%m%d")):
            # open the file and look for the first date that is greater
            # if that is tne next sequence number, insert it and loop to end
            # if not, we tried, we failed.  Will have to download files from OLA
            f = open(fn, "rt")
            for fline in f:
                fdata = OLAdata(fline.encode("ascii", "ignore"))
                if fdata.obsDateTime > (lastDate+one_second):
                    if fdata.obsNum == (lastSeqNum+1):
                        if write_database(fdata) == True:
                            lastDate = fdata.obsDateTime
                            lastSeqNum = fdata.obsNum
                            success = True
                            print('Successfully wrote: ', end='')
                            old_print(fdata.inString, end='', flush=True)
                        else:
                            success = False
                            f.close()
                            print("\nDatabase write failed.  Failed attempt to catch database up from logged files.")
                            return success
                    else:
                        success = False
                else:
                    success = False
            f.close()
            
    if success == True:
        print("\nSuccessfully caught database up using logged data files.")
    else:
        print("\nFailed attempt to catch database up from logged files.")
    return success

# If we recently downloaded data files and need to re-sync the data, we will
# read through the data files to re-sync.
def update_db_from_data_files():
    success = False
    one_second = timedelta(seconds=1)
    # This is a modification of update_db_from_logged_files.
    #
    # get the last entry in the db
    # check to see if we have the next sequence number in the data files
    # if so, write it to the db.  Do this until caught up
    prevData = OLAdata('')    
    print("Attempting to catch database up from data files.")
    
    db_url = config['dataHandler']['DB_URL'] + "/latest_water_level"
    get_data = { 'key':config['dataHandler']['API_KEY'],
                 'sensor_id':config['dataHandler']['SITE_ID'] }
    try:
        rd = requests.get(url=db_url, params=get_data)
    except:
        success = False
        return prevData
        
    print(rd.url)
    print(rd.text)
    j = rd.json()
    lastDate = datetime.strptime(j[0]["date"], "%Y-%m-%d %H:%M:%S")
    UTCtoEST = timedelta(hours=5)
    lastDate = lastDate - UTCtoEST
    print(lastDate)

    # get a list of data files - since the dates in them are unknown, have to open them all
    flist = glob.glob(config['dataHandler']['DOWNLOADED_FILE_DIR']+'/dataLog?????.TXT')
    flist.sort()   # sort the file list ascending
    for fn in flist:
        # open the file and look for the first date that is greater
        # ignoring seqNum going by date only. insert it and loop to end
        # if not, we tried, we failed.  Will have to try again
        f = open(fn, "rt")
        for fline in f:
            fdata = OLAdata(fline.encode("ascii", "ignore"))
            if fdata.inString != '':    # if the line fails parsing we will skip it.
                if fdata.obsDateTime > (lastDate+one_second):
                    if write_database(fdata) == True:
                        lastDate = fdata.obsDateTime
                        prevData = fdata
                        success = True
                        print('Successfully wrote: ', end='')
                        old_print(fdata.inString, end='', flush=True)
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


# Command sequence to access the OLA and download the necessary data files.
def download_data_files():
# Download any data files from the OLA that we dont have or are a different size
# returns the most recent observation
#
# Get filenames and sizes from the OLA and from local storage
#    Check for OLA file number restart (new card, new OLA)
#    If so, archive the existing files and download all
# Remove matching entries (same name and size)
# Download anything remaining in the OLA list
# Update the database from these files (in the list)

    prevData = OLAdata('')
    fileDir = config['dataHandler']['DOWNLOADED_FILE_DIR']
    
    ss = fdpexpect.fdspawn(ser)    # set up to use ss with pexpect
    
    ola_fdict = get_OLA_file_list(ss)
    if len(ola_fdict)==0:
        return prevData    # we failed

    flist = os.listdir(fileDir)
    for fn in flist:
        sz = os.path.getsize(fileDir+"/"+fn)
        # Remove the files we already have from the ola file list
        if fn in ola_fdict and sz == ola_fdict.get(fn):
            ola_fdict.pop(fn, None)
            
    # If the ola_fdict has any filenames other than the latest,
    # the file numbers might have reset (or some other problem has happened).
    # Archive all the files that we have before we download the list.
    if len( set(flist[:-1]).intersection(ola_fdict.keys()) ) > 0:
        print('WARNING: Archiving data files due to repeat download of finished file. (New OLA? File numbers reset?)')
        archive_dir = fileDir + '/Archived-' + datetime.today().strftime('%Y%m%d%H%M%S')
        os.chdir(fileDir)    # need to be here for zmodem receive
        os.mkdir(archive_dir)
        os.system('mv *.* '+archive_dir)
            
    # Send the files in ola_fdict in order in case of a failure
    os.chdir(fileDir)    # need to be here for zmodem receive
    sorted_filedict = sorted(ola_fdict)
    for fn in sorted_filedict:
        print("Sending: " + fn, flush=True)
        time.sleep(1)
        ss.sendline('sz '+ fn)
        time.sleep(1)
        os.system("rz --overwrite > /dev/rfcomm0 < /dev/rfcomm0")
        
    # update the database with the new data and set prevData to most recent
    prevData = update_db_from_data_files()
    exit_zmodem(ss)
    return prevData


# Procedure for retrieving the list of files on the OLA
def get_OLA_file_list(ss):
# get a dictionary of files and file sizes from the OLA
    fileDict = {}    # declare empty dictionary
    
    if get_OLA_menu(ss)==False:
        return fileDict    # empty dict 
    try:
        ss.send('s')
        ss.expect('ZModem', timeout=10)
    except Exception as ex:
        print("Exception waiting for ZModem menu")
        template = "An exception of type {0} occurred. Arguments:\n{1!r}"
        message = template.format(type(ex).__name__, ex.args)
        print(message)
        print("debug information:")
        print(str(ss))
        exit_zmodem(ss)
        return fileDict
    time.sleep(2)
    try:
        ss.sendline('dir')
        ss.expect('End of Directory', timeout=10)
    except Exception as ex:
        print("Exception waiting for file directory")
        template = "An exception of type {0} occurred. Arguments:\n{1!r}"
        message = template.format(type(ex).__name__, ex.args)
        print(message)
        print("debug information:")
        print(str(ss))
        print(ss.before)
        exit_zmodem(ss)
        return fileDict
    # Now parse the before to look for dataLog?????.txt and the token before it which is size
    blines = ss.before.splitlines()
    for ll in blines:
        if ll.find(b'dataLog') != -1:
            lls = ll.split()
            fileDict.update({ lls[3].decode() : int(lls[2]) })
    return fileDict


# Procedure for exiting the zmodem menu on the OLA
def exit_zmodem(ss):
    print("Exiting zmodem")
    try:
        time.sleep(1)
        ss.sendline('x')
        ss.expect('Menu: Main Menu')
        time.sleep(1)
        ss.sendline('x')
        ser.reset_input_buffer()    # flush the rest of the menu text
    except Exception as ex:
        print("Exception during exit waiting for main menu")
        template = "An exception of type {0} occurred. Arguments:\n{1!r}"
        message = template.format(type(ex).__name__, ex.args)
        print(message)
        print("debug information:")
        print(str(ss))


# Procedure to access OLA menu.  If called at the right time it could be quick,
# otherwise it will hammer on the OLA until it wakes up for the next observation.
def get_OLA_menu(ss):
    ss.sendline(' ')    # before print to be fast
    print("Attempting to open main menu")
    found=1    # will become 0 when found
    while found==1:
        try:
            ss.sendline(' ')
            found=ss.expect(['Menu: Main Menu', pexpect.TIMEOUT], timeout=0.3)
        except Exception as ex:
            print("Exception waiting for main menu")
            template = "An exception of type {0} occurred. Arguments:\n{1!r}"
            message = template.format(type(ex).__name__, ex.args)
            print(message)
            print("debug information:")
            print(str(ss))
            return False  # if we get an exception we are done
        old_print(".", end='', flush=True)
    print("Found Main Menu")
    time.sleep(1)
    return True
        

def main():
    newData = OLAdata('')       # initialize empty
    keepPrevData = True         # init to true so first loop doesn't overwrite prevData
    DB_OUT_OF_SYNC = False
    BT_ERROR = False
    was_bt_err = False
    want_file_download = True
    RESTLESS = 0.0001   # sleep time in seconds (RasPi 4 will sleep about .0002 for its minimum)
    MELLOW = 1
    sleep_time = RESTLESS
        
    while True:
        try:
            nchars = ser.in_waiting
            BT_ERROR = False
        except:  # comm port must be down
            nchars = 0
            BT_ERROR=True
            ser.close()
            time.sleep(10)
            ser.open()
            time.sleep(10)
            
        if was_bt_err==False and BT_ERROR==True:
            print("Bluetooth error, waiting for comm port.", flush=True)
        if was_bt_err==True and BT_ERROR==False:
            print("Comm port restored.", flush=True)
        was_bt_err = BT_ERROR
        
        # If we need the menu, we have to be fast.  Sleep time will be set to minimum, and as soon
        # as we see the first character show up, we try sending a char.  Maybe,
        # if we are fast enough that will get into the menu without hammering on bluetooth.
        # At 115200, chars come every ~.0001 s: min resolution on the pi is about .0002.
        # If this fails, we will be in the regular get_OLA_menu routine that hammers on bluetooth
        # until it succeeds.
        #
        if nchars > 0:
            if want_file_download == True:
                prevData = download_data_files()
                want_file_download = False
                keepPrevData = True    # keep us from overwriting prevData
                sleep_time = MELLOW
                print('prevData set to: ', end='')
                old_print(prevData.inString, end='', flush=True)
                continue
            incomingLine = ser.read_until(b'\n')
            istr = incomingLine.decode("utf-8", "ignore")   # remove non-ascii chars
            incomingLine = istr.encode("ascii", "ignore")
            if len(incomingLine)==0:   # line was only garbage
                continue
            if keepPrevData==False:
                prevData = newData        # save the previous data if it was good
            newData = OLAdata(incomingLine)              # create a class to hold the data
            print(newData.inString, end='', flush=True)
            if newData.inString=='':        # failed parse
                keepPrevData = True
                print("Failed parse: ", end='')
                old_print(incomingLine.decode(), flush=True)
            else:
                keepPrevData = False
                if check_sequential(newData, prevData)==False:
                    print('Sequence number not sequential. Downloading data files to catch up.', flush=True)
                    want_file_download = True
                    sleep_time = RESTLESS
                    keepPrevData = True  # whether it really failed or not, we want to keep prevData
                if check_sequential(newData, prevData)==True:  # check again, not else
                    write_local_file(newData)
                    if DB_OUT_OF_SYNC == True:     # this can happen if the db write fails
                        if update_db_from_logged_files() == True:
                            DB_OUT_OF_SYNC = False
                    if DB_OUT_OF_SYNC == False:    # check again - don't use else!
                        # write the incoming data to local file and database
                        DB_OUT_OF_SYNC = not write_database(newData)
                    
        time.sleep(sleep_time)

# Call main if necessary
if __name__ == "__main__":
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
    

    ser = serial.Serial('/dev/rfcomm0', 115200, timeout=1)
    print('Opened: ' + ser.name, flush=True)    # just checking the name
    time.sleep(10)

    main()
    