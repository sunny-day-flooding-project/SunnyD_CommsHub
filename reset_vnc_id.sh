#!/bin/bash

echo "Stopping VNC service..."
sudo systemctl stop vncserver-x11-serviced

echo "Removing VNC identity (Cloud ID & keys)..."
sudo rm -rf /root/.vnc

echo "Starting VNC service..."
sudo systemctl start vncserver-x11-serviced

echo "Identity removed"
echo "Reconnect through the user interface."

