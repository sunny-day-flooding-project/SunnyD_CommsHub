#!/bin/bash
echo `date` " " `hostname` " " `curl -s https://ipinfo.io/ip` >> /home/pi/ALL_GATEWAYS/ip_addresses.log
