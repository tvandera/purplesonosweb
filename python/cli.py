#!/usr/bin/env python3
import sys
import requests
import urllib.parse
from tabulate import tabulate
from glom import glom, T

BASE_URL = "http://127.0.0.1:9999/api"


def usage(msg=None):
    if msg:
        print(f"Error: {msg}")
    print("Usage:")
    print("  cli.py music")
    print("  cli.py search <term>")
    print("  cli.py zones")
    print("  cli.py <zone> queue")
    print("  cli.py <zone> zone")
    print("  cli.py <zone> start|pause|stop|next|previous|volume <val>|mute|unmute")
    sys.exit(1)


def do_request(**params):
    query = "&".join(f"{urllib.parse.quote(k)}={urllib.parse.quote(str(v))}" for k, v in params.items())
    url = f"{BASE_URL}?{query}"
    response = requests.get(url)
    response.raise_for_status()
    return response.json()


def show_info(what, data):
    specs = {
        "search" : ( T.values(), [{
            'id' : ( 'id', T[0:20] ),
            'title' : 'name',
            'class' : 'class',
            'album' : 'album',
            'artist' : 'creator'
        }]),
        "queue" : [{
            'pos' : 'pos',
            'title' : 'name',
            'album' : 'album',
            'artist' : 'creator'
        }],
        "zones" : (T.values(), [
            { 'name' : 'zone.name',
              'state' : 'av.transport_state',
              'volume' : 'render.volume',
            },
        ]),
    }

    rows = glom(data, specs[what])
    print(tabulate(rows, headers="keys"))


def global_info(what, *args):
    params = {"what": what}
    if what == "search":
        if not args:
            usage("Missing search term")
        params["msearch"] = args[0]
        params["what"] = "music"
    elif what == "music":
        params["mpath"] = args[0] if args else ""
    data = do_request(**params)
    show_info(what, data)


def zone_info(zone, what, *args):
    params = {"zone": zone, "what": what}
    data = do_request(**params)
    show_info(what, data)


def zone_command(zone, command, *args):
    params = {"zone": zone, "action": command}
    if command == "volume":
        if not args:
            usage("Missing volume level")
        params["volume"], = args
    if command == "play":
        if not args:
            usage("Missing music path")
        params["mpath"], = args
    if command == "seek":
        if not args:
            usage("Missing queue index")
        params["queue"], = args
    do_request(**params)


def main():
    actions = {"start", "pause", "stop", "next", "previous", "volume", "mute", "unmute", "play", "seek"}
    global_cmds = {"music", "search", "all", "zones"}
    per_zone = {"queue", "zone"}

    if not sys.argv[1:]:
        return global_info("zones")

    arg1 = sys.argv[1]
    if arg1 in global_cmds:
        return global_info(*sys.argv[1:])

    if len(sys.argv) < 3:
        usage()

    zone, command, *args = sys.argv[1:]
    if command in per_zone:
        return zone_info(zone, command, *args)
    elif command in actions:
        return zone_command(zone, command, *args)
    else:
        usage()


if __name__ == "__main__":
    main()
