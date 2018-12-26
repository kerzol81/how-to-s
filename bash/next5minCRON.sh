#!/bin/bash

# how many seconds have left until next 5-minute-cyclic cron job
set -x

date +"%H:%M:%S" >>test2.txt

CURRENT_MINUTES=$(date +'%M' | cut -c 2-)
CURRENT_SECONDS=$(date +'%-S')

if [ "$CURRENT_MINUTES" -eq 0 ] && [ "$CURRENT_SECONDS" -eq 0 ]; then
	exit 0
elif [ "$CURRENT_MINUTES" -eq 5 ] && [ "$CURRENT_SECONDS" -eq 0 ]; then
	exit 0
elif [ "$CURRENT_MINUTES" -gt 0 ] && [ "$CURRENT_MINUTES" -lt 5 ];then
	R=$((300-(CURRENT_MINUTES*60+CURRENT_SECONDS)))
	
elif [ "$CURRENT_MINUTES" -gt 5 ] && [ "$CURRENT_MINUTES" -lt 10 ];then
	R=$((600-(CURRENT_MINUTES*60+CURRENT_SECONDS)))	
else
	exit 1
fi

echo "$R" >> test2.txt

exit 0
