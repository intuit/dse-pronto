#!/bin/bash

#set -x
uptime=$(nodetool info | grep -i uptime | awk -F ':' '{print $2}')
start_time=$(TZ=America/Los_Angeles date --date "- $uptime seconds")
uptime_in_days=$(awk "BEGIN {print $uptime / 86400 }")
echo "DSE was started at : $start_time and it is up since $uptime_in_days days"
