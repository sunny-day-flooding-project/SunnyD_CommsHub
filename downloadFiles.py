#
# downloadFiles is derived from
# Data handler
#
# Just tries to download a list of data files from the OLA
# This is useful when the BLE connection is terrible and we want to keep trying over 
# and over to get little bits of data at a time.
#
# Written Oct 2024 by Tony Whipple
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
import re
from os.path import exists
import glob
from datetime import datetime
from datetime import timedelta
from configobj import ConfigObj
import traceback


# 
# SET THESE UP BEFORE RUNNING
#
startFile = 80
endFile = 266



# override print so each statement is timestamped
old_print = print
def timestamped_print(*args, **kwargs):
  old_print(datetime.now(), *args, **kwargs)
print = timestamped_print

# if we catch a signal from the OS, clean up and exit
def signal_handler(sig, frame):
    # ignore additional signals
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGQUIT, signal.SIG_IGN)
    signal.signal(signal.SIGILL, signal.SIG_IGN)
    signal.signal(signal.SIGABRT, signal.SIG_IGN)
    signal.signal(signal.SIGFPE, signal.SIG_IGN)
    signal.signal(signal.SIGSEGV, signal.SIG_IGN)
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
            

# Command sequence to access the OLA and download the necessary data files.
def download_data_files(ss):
# Download any data files from the OLA that we dont have or are a different size
# returns the most recent observation
#
# Get filenames and sizes from the OLA and from local storage
#    Check for OLA file number restart (new card, new OLA)
#    If so, archive the existing files and download all
# Remove matching entries (same name and size)
# Download anything remaining in the OLA list
# Update the database from these files (in the list)
#
# A situation arose where the file numbering started over on the OLA, yet there
# were many files with larger numbers.  This triggered an archival and full download
# of files each time download_data_files was called.  Apart from being unnecessary, that
# put a huge load on the batteries of the sensor.  Therefore I am changing the algorithm
# to be for only files with a number less than or equal the current file number.
#
    global startFile
    
    prevData = OLAdata('')
    fileDir = config['dataHandler']['DOWNLOADED_FILE_DIR']
        
    # Errors in the transmission of the OLA file list are costly. Try up to 5 times to get 
    # two identical copies in a row before we call it a good transmission.
    if get_OLA_menu(ss)==False:
        return prevData    # failed to get menu 
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
        return prevData
    time.sleep(2)

    try:
        ola_fdict = get_OLA_file_list(ss)   # the file list is sorted in date order
    except Exception as ex:
        print("Exception waiting for ZModem menu")
        template = "An exception of type {0} occurred. Arguments:\n{1!r}"
        message = template.format(type(ex).__name__, ex.args)
        print(message)
        print("debug information:")
        print(str(ss))
        exit_zmodem(ss)
        return prevData


    # The next two lines get the local file list and sorts them in date order
    os.chdir(fileDir)
    flist = sorted(filter(os.path.isfile, os.listdir(fileDir)), key=os.path.getmtime)
                                
    # Send the files in ola_fdict
    try:
        for fn in ola_fdict:
            # result>>8 gives the exit status of the process.  If the file transfer fails, get out
            print("Sending: " + fn, flush=True)
            time.sleep(1)
            ss.sendline('sz '+ fn)
            time.sleep(1)
            result = os.system("rz -r -U > /dev/rfcomm0 < /dev/rfcomm0")
            while (result >> 8) != 0:
                print("Sending: " + fn, flush=True)
                time.sleep(1)
                ss.sendline('sz '+ fn)  # try twice - might work
                time.sleep(1)
                ss.sendline('sz '+ fn)
                time.sleep(1)
                result = os.system("rz -r -U > /dev/rfcomm0 < /dev/rfcomm0")
                
            startFile = startFile + 1   # if we succeeded, go on to the next file
    except Exception as ex:
        print("Exception during file transfer")
        template = "An exception of type {0} occurred. Arguments:\n{1!r}"
        message = template.format(type(ex).__name__, ex.args)
        print(message)
        print("debug information:")
        print(str(ss))
        print(ss.before)
        return prevData
        
    exit_zmodem(ss)
    return prevData


# Procedure for retrieving the list of files on the OLA
#
# In this version we will not try to get a file list from the OLA,
# but rather just construct one based on a numeric range.
#
def get_OLA_file_list(ss):
# get a dictionary of files and file sizes from the OLA sorted in date order
    global startFile
    global endFile
    fileDict = {}    # declare empty dictionary
    dtDict = {}
    
    for i in range(startFile, endFile+1): # range goes from startFile up to but not including the last argument
        fileDict.update( {'dataLog' + str(i).zfill(5) + '.TXT' : 0} )
    
    return fileDict


# Procedure for exiting the zmodem menu on the OLA
def exit_zmodem(ss):
    for tries in range(3):      # try thrice, it's important
        try:
            print("Attempting to exit zmodem")
            time.sleep(1)
            ss.sendline('x')
            ss.expect('Menu: Main Menu')
            time.sleep(1)
            ss.sendline('x')
            ser.reset_input_buffer()    # flush the rest of the menu text
            break                       # get out of the tries loop if we succeed
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
        except pexpect.exceptions.EOF as e:
            print("Caught EOF error - waiting for port to re-appear")
            ser.close()
            while not exists('/dev/rfcomm0'):
                time.sleep(3)
            ser.open()
            time.sleep(1)
            continue
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
    prevData= OLAdata('')
    keepPrevData = True         # init to true so first loop doesn't overwrite prevData
    DB_OUT_OF_SYNC = False
    BT_ERROR = False
    was_bt_err = False
    want_file_download = True
    RESTLESS = 0.0001   # sleep time in seconds (RasPi 4 will sleep about .0002 for its minimum)
    MELLOW = 1
    sleep_time = RESTLESS
    data_delay_start_time = time.time() # time how long since data in case we are stuck in the file transfer menu
    MAX_DATA_DELAY = config['dataHandler']['MAX_DATA_DELAY']
    no_logging = config['dataHandler']['DB_URL'].lower().startswith('no')
    ss = fdpexpect.fdspawn(ser, maxread=65536)    # set up to use ss with pexpect
    #ss.logfile = sys.stdout.buffer     # enable this line to see the output (python3)
    
    while True:
        try:
            nchars = ser.in_waiting
            #print(nchars)
            BT_ERROR = False
        except:  # comm port must be down
            nchars = 0
            BT_ERROR=True
            try:        # these serial operations can raise another exception if they have not completed
                if(ser.isOpen() == True):
                #if was_bt_err==False:
                    print("Closing serial port.", flush=True)
                    ser.close()
                    time.sleep(3) # these used to be 10 s each.
                if exists('/dev/rfcomm0'):
                    ser.open()
                    time.sleep(3)
            except:
                time.sleep(3)
            data_delay_start_time = time.time()     # keep restarting the timer while bluetooth port is down
            
        if was_bt_err==False and BT_ERROR==True:
            print("Bluetooth disconnected (or other error), waiting for comm port.", flush=True)
        if was_bt_err==True and BT_ERROR==False:
            print("Comm port restored.", flush=True)
            data_delay_start_time = time.time()     # restart the timer if we have just regained bluetooth
        was_bt_err = BT_ERROR
        
        
        # If we need the menu, we have to be fast.  Sleep time will be set to minimum, and as soon
        # as we see the first character show up, we try sending a char.  Maybe,
        # if we are fast enough that will get into the menu without hammering on bluetooth.
        # At 115200, chars come every ~.0001 s: min resolution on the pi is about .0002.
        # If this fails, we will be in the regular get_OLA_menu routine that hammers on bluetooth
        # until it succeeds.
        #
        if nchars > 0:
            data_delay_start_time = time.time() # we received something so reset the timer
            if want_file_download == True:
                prevData = download_data_files(ss)
                data_delay_start_time = time.time() # this could have taken a long time
                want_file_download = False
                keepPrevData = True    # keep us from overwriting prevData
                sleep_time = MELLOW
                print('prevData set to: ', end='')
                if not prevData.inString:
                    old_print('(null)')
                else:
                    old_print(prevData.inString, end='', flush=True)
                continue
            try:
                incomingLine = ser.read_until(b'\n')
            except Exception as ex:
                print("Exception reading serial data.  Continuing.")
                template = "An exception of type {0} occurred. Arguments:\n{1!r}"
                message = template.format(type(ex).__name__, ex.args)
                print(message)
                continue
            istr = incomingLine.decode("utf-8", "ignore")   # remove non-ascii chars
            incomingLine = istr.encode("ascii", "ignore")
            if len(incomingLine)==0:   # line was only garbage
                continue
            want_file_download = True
            sleep_time = RESTLESS
        
        # no chars
        time.sleep(sleep_time)
        if time.time() - data_delay_start_time > float(MAX_DATA_DELAY):
            exit_zmodem(ss)
            data_delay_start_time = time.time()

# Call main if necessary
if __name__ == "__main__":

    while True:
        try:
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
            
            device_file = '/dev/rfcomm0'
            print('Attempting to open ' + device_file, end='')
            while not exists(device_file):
                old_print('.', end='')
                time.sleep(3)
            old_print(' ')
                
            ser = serial.Serial(device_file, 115200, timeout=3) # changed timeout from 1 to 3 on 20220711
            print('Opened: ' + ser.name, flush=True)    # just checking the name
            time.sleep(10)

            main()
        except Exception as ex:
            print("Unhandled exception in __main__")
            print("Sleeping 60s and starting over.")
            template = "An exception of type {0} occurred. Arguments:\n{1!r}"
            message = template.format(type(ex).__name__, ex.args)
            print(message)
            print(traceback.format_exc())
            time.sleep(60)
        