#!/bin/sh

cd "$(dirname "$0")"

while true;
do
	nohup perl sonos.pl >sonos-$(date +%Y%m%d_%H%M).log 2>&1 &
	sleep 1m
done
