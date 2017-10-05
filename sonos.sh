#!/bin/sh

cd "$(dirname "$0")"

nohup perl sonos.pl >sonos-$(date +%Y%m%d_%H%M).log 2>&1 &
