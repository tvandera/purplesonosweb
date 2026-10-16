#!/bin/sh
set -eu

Xvfb :0 -screen 0 1280x800x24 -ac -nolisten tcp &
xvfb_pid=$!
export DISPLAY=:0

if [ -n "${PROXY_SERVER:-}" ]; then
    export http_proxy="$PROXY_SERVER" https_proxy="$PROXY_SERVER"
fi

eval "$(dbus-launch --sh-syntax)"
if [ -n "${ANDROID_44_USER_AGENT:-}" ]; then
    gsettings set org.gnome.Epiphany user-agent "$ANDROID_44_USER_AGENT"
fi

startlxde &
desktop_pid=$!

epiphany-browser "${TEST_URL:-about:blank}" &

cleanup() {
    kill "$desktop_pid" "$xvfb_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

exec x11vnc -display :0 -forever -shared -passwd "${VNC_PASSWORD:?VNC_PASSWORD must be set}" -listen 0.0.0.0 -rfbport 5900 -noxdamage
