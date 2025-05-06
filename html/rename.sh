#!/bin/bash

REPLACEMENTS="
    zone_arg/args.zone
    music_arg/args.mpath
    all_arg/args.all
    has_active_zone/args.zone
    "

for R in $REPLACEMENTS
do
    sed -i -e "s/$R/g" *.html  */*.html */*.tmpl
done