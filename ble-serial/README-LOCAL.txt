This was forked from https://github.com/Jakeler/ble-serial.

Three files have been modified in this version (ble_client.py, main.py, and linux_pty.py) in an
attempt to keep ble-serial from crashing during weak/intermittent BLE connections.  
When ble-serial crashes enough times, resources are used up and the underlying bleak/BlueZ system 
becomes unstable requiring a reload/reboot.
