#!/bin/bash
#

F=$1

wget -O - \
    --header='SOAPACTION: "urn:schemas-upnp-org:service:RenderingControl:1#SetVolume"' \
    -d -S --post-file=$F http://192.168.2.200:1400/MediaRenderer/RenderingControl/Control
