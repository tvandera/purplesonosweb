var iSonos = {};
/**** CONFIG BEGIN ****/
// Host Sonos Web Controller is running on
iSonos.host = "192.168.2.13";

// Port Sonos Web Controller is running on
iSonos.port = 9999;

// EXACT Name of Zone you want to control
iSonos.zone = "Kitchen";

/**** CONFIG END ****/


/**** iSonos Replacement ****/
iSonos.backTrack = function () {
    sonos.sendControlAction(iSonos.zoneId, "Previous");
}
iSonos.nextTrack = function () {
    sonos.sendControlAction(iSonos.zoneId, "Next");
}
iSonos.fastForward = function () {
    log("fastForward");
}
iSonos.pause = function () {
    sonos.sendControlAction(iSonos.zoneId, "Pause");
}
iSonos.play = function () {
    sonos.sendControlAction(iSonos.zoneId, "Start");
}
iSonos.playPause = function () {
    var zone = sonos[iSonos.zoneId];
    if (zone.mode == 1) {
        sonos.sendControlAction(iSonos.zoneId, "Pause");
    } else {
        sonos.sendControlAction(iSonos.zoneId, "Start");
    }
}
iSonos.resume = function () {
    sonos.sendControlAction(iSonos.zoneId, "Start");
}
iSonos.rewind = function () {
    log("rewind");
}
iSonos.stop = function () {
    sonos.sendControlAction(iSonos.zoneId, "Pause");
}
iSonos._propertyChange = function (id, oldval, newval) {
    if ((oldval == newval) || iSonos._ignorePropertyChange) {
        return newval;
    }

    if (id == "volume") {
        sonos.setVolume(iSonos.zoneId, newval);
    } else if ((id == "shuffle") || (id == "random")) {
        if (newval) {
            sonos.sendControlAction(iSonos.zoneId, "ShuffleOn");
        } else {
            sonos.sendControlAction(iSonos.zoneId, "ShuffleOff");
        }
    } else if (id == "repeatMode") {
        if (newval == "off") {
            sonos.sendControlAction(iSonos.zoneId, "RepeatOff");
        } else {
            sonos.sendControlAction(iSonos.zoneId, "RepeatOn");
        }
    }

    return newval;
}

const http = require("http");

/**** Sonos JS Stuff ****/



function drawZones() {
    for (i = 0; i < sonos.zones.length; i++) {
        if (sonos[sonos.zones[i]].zoneName == iSonos.zone) {
            iSonos.zoneId = sonos[sonos.zones[i]].zoneId;
            return;
        }
    }
    alert("Could not find specified zone name '" + iSonos.zone + "'");
}

function drawControl(zoneId) {
    if (zoneId != iSonos.zoneId) return;

    var zone = sonos[zoneId];

    iSonos._ignorePropertyChange = 1;
    if (zone.mode == 0) {
        iSonos.playerStatus = "stopped";
    } else if (zone.mode == 1) {
        iSonos.playerStatus = "playing";
    } else {
        iSonos.playerStatus = "paused";
    }
    iSonos.playerPosition = zone.position;
    if (zone.shuffle) {
        iSonos.random = true;
        iSonos.shuffle = true;
    } else {
        iSonos.random = false;
        iSonos.shuffle = false;
    }
    if (zone.repeat) {
        iSonos.repeatMode = "all";
    } else {
        iSonos.repeatMode = "off";
    }
    iSonos.running = 1;
    iSonos.trackAlbum = zone.album;
    iSonos.trackArtist = zone.artist;
    iSonos.trackLength = zone.trackLen;
    iSonos.trackTitle = zone.song;
    iSonos.trackType = "audio file";
    iSonos.volume = zone.volume;
    iSonos._ignorePropertyChange = 0;
    if (!iSonos._inited) {
        iSonos._inited = 1;
        iSonos.watch("volume", iSonos._propertyChange);
        iSonos.watch("random", iSonos._propertyChange);
        iSonos.watch("shuffle", iSonos._propertyChange);
        iSonos.watch("repeatMode", iSonos._propertyChange);
    }
}

function drawQueue(zoneId) {
}

function drawMusic(path) {
}

sonos = {};

// Replace the load data
sonos._loadData = function (filename, afterFunc) {
    // Load sonos.js from the server
    http.get("http://" + iSonos.host + ":" + iSonos.port + "/status.json", res => {
        let data = [];
        res.on('data', chunk => {
            console.log("got: ", chunk);
            data.push(chunk);
        });
        res.on('end', () => {
            console.log("finished: ", Buffer.concat(data).toString());
        });
    }).on('error', err => {
        console.log('Error: ', err.message);
    });
}

// Replace
sonos._fetch = function () {
    sonos._doFetch();
}

sonos.start = function() {
    sonos._loadData();
}

/**** Main ****/
sonos.start();
