#!/bin/bash

REPLACEMENTS="
    zone_arg/args.zone
    music_arg/args.mpath
    all_arg/args.all
    has_active_zone/args.zone
    music_(\\w+)/music.\\1
    queue_(\\w+)/item.\\1
    ZONE_FANCYNAME/player.zone.name
    "

for R in $REPLACEMENTS
do
    sed -i -e "s/$R/g" *.html  */*.html */*.tmpl
done