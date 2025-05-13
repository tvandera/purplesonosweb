/* Sample Sonos JS App.
 * sonos.js must be included before this file
 *
 * It makes some big assumptions how things will be done.
 * Of course you don't have to use this to write your app.
 *
 */
"use strict";

var app = {};

function updateText(name, text) {
    var element = document.getElementById(name);
    if (element && (!element.innerHTML || element.innerHTML != text)) {
        element.innerHTML = text;
    }
}

function updateSrc(name, src) {
    var element = document.getElementById(name);
    if (!element) return;
    if (!src) {
        element.style.display = "none"
    } else {
        element.src = src
        element.style.display = "inline"
    }
}

function updateToggle(first, second, doFirst) {
    document.getElementById(first).style.display = (doFirst?"inline":"none");
    document.getElementById(second).style.display  = (doFirst?"none":"inline");
}

function mSelectLabel(name) {
    var labels = [ "currentzone", "nowplaying", "music", "queue" ];
    for (let i=0; i < labels.length; i++) {
        var n = labels[i];
        if (name == n) $('#' + n + "label").css("background", "#666");
        else $('#' + n + "label").css("background", "#000");
    }
}

function start() {
    app.currentMusicPath = "";
    app.musicPathStack = [];
    app.rootLastUpdate = 0;
    sonos.start();
    drawZones();
}

function setCurrentZone(zoneId) {
    app.currentZoneName = zoneId;
    drawControl(zoneId);
    drawMusic(app.currentMusicPath);
    drawQueue(zoneId);
    drawZones();
}

function needZone() {
    if (!app.currentZoneName) {
        alert("Please select a Zone first.");
        return 1;
    }
    return 0
}

function doAction(action) {
    if (needZone()) return;
    sonos.sendControlAction(app.currentZoneName, action);
}

function doQAction(action, id) {
    if (needZone()) return;
    sonos.sendQueueAction(app.currentZoneName, action, id);
}

function doMAction(action, path) {
    if (needZone()) return;
    sonos.sendMusicAction(app.currentZoneName, action, path);
}

function browseBack() {
    if (app.musicPathStack.length == 0) return;
    browseTo(app.musicPathStack.pop(), true);
}

function browseTo(path,nobreadcrumbs) {
    if (!nobreadcrumbs) app.musicPathStack.push(app.currentMusicPath);
    app.currentMusicPath = path;

    if (sonos.music[app.currentMusicPath]) {
        drawMusic(app.currentMusicPath);
    } else {
        sonos.sendMusicBrowse(app.currentMusicPath);
    }
}

function doLink(zone) {
    sonos.sendAction(app.currentZoneName, "Link", "&link="+zone);
}

function doUnlink(zone) {
    sonos.sendAction(app.currentZoneName, "Unlink", "&link="+zone);
}

function drawZones() {
    var str = "";
    for (let i = 0; i<sonos.zones.length; i++) {
        var zone = sonos.zones[i];
        str += "<ul onClick=\"setCurrentZone('" + zone.name + "')\">";
        // str += "<li style='background-image: url("+ zone.zone.img+");'>";
        str += zone.zone.name;
        str += "</li>\n";
        str += "</ul>";
    }
    updateText("zones", str);
}

function curZoneInfo() {
    for (let z in sonos.zones) {
        var zone = sonos.zones[z];
        if (zone.name != app.currentZoneName) continue;
        return zone;
    }
}

function drawControl(zoneId) {
    if (zoneId != app.currentZoneName) return;
    var player = curZoneInfo();

    updateText('currentzonename', player.zone.name);
    updateText('song', player.av.track);
    updateText('album', player.av.album);
    updateText('artist', player.av.artist);
    updateToggle("pause", "play", player.av.isplaying);
    updateToggle("muteoff", "muteon", player.render.ismuted);
    updateText('volume', player.render.volume);
    var image = player.av.albumart;
    if (!image) image = "tiles/missingaa_lite.svg";
    updateSrc('albumart', image);
    drawQueue(zoneId);
}

function drawQueue(zoneId) {
    if (zoneId != app.currentZoneName) return;
    var queue = curZoneInfo().queue;
    var cur_track = curZoneInfo().active_track_num;
    var zone_paused = curZoneInfo().active_paused_playback;
    var zone_playing = curZoneInfo().active_playing;

    var str = new Array();
    str.push("<ul>");

    //header
    str.push("<li class='header'>");
    str.push("<img src='svg/queue.svg'>");
    str.push("<div><p>&nbsp;</p>");
    str.push("<p class='buttons'><a onclick=\"doAction('RemoveAll')\">Remove All</a></p>");
    str.push("</div></li>");

    if (queue.length == 0) {
        str.push("<li>The queue is emtpy</li>");
    } else for (let i=0; i < queue.items.length; i++) {
        var item = queue.items[i];
        var paused = (cur_track == item.QUEUE_TRACK_NUM) && zone_paused;
        var playing = (cur_track == item.QUEUE_TRACK_NUM) && zone_playing;

        let action;
        if (paused)       action = "doAction('Start');";
        else if (playing) action = "doAction('Pause');"
        else              action = "doQAction('Seek', '" + item.queue_id + "'); doAction('Start');";
        str.push("<li onClick=\"" + action + "\">");

        let img;
        if (paused) img = 'svg/pause.svg';
        else if (playing) img = 'svg/pause.svg';
        else img = item.albumart;
        str.push("<img class='albumart' src='" + img + "'>");

        str.push("<div><p class='title'>" + item.title + "</p>");
        str.push("<p class='artist'>" + item.artist + "</p>");
        str.push("</div>");
        str.push("</li>");
    }
    str.push("</ul>");
    updateText("queuedata", str.join(""));
}

function drawMusic(path) {
    var info = sonos.music[path];
    var str = new Array();

    // header with path title
    str.push("<ul id='musiclist' data-role='listview' data-autodividers='true'>");
    if (! info.istop) {
        str.push("<li class='header'>");
        str.push("<img onClick='browseBack()' src='tiles/back.svg'>");
        str.push("<div><p id='musicpath'>" + info.title + "</p>");
        if (info.artist) str.push("<p class='artist'>" + info.artist + "</p>");
        if (info.isalbum) {
            str.push("<p class='buttons'><a HREF='#' onClick='doMAction(\"Play\", \"" + path + "\");'>Play</A> - <a HREF='#' onClick='doMAction(\"add\", \"" + path + "\");'>Add</A></p>");
        }
        str.push("</div></li>");

        if (info.albumart && info.isalbum) {
            str.push("<li class='albumart'><img onerror='this.src=\"tiles/missingaa_lite.svg\";' src='" + info.albumart + "'></li>");
        }
    }

    // container items
    for (var i=0; i < info.items.length; i++) {
        var item = info.items[i];
        path = decodeURIComponent(item.id);
        str.push("<li");
        if (item.isradio)
            str.push(" onClick='doMAction(\"Play\", \"" + path + "\");'>");
        else
            str.push(" onClick='browseTo(\"" + path + "\")'>");

            if (item.iscontainer) {
                str.push("<img onerror='this.src=\"tiles/missingaa_dark.svg\";' src='" + decodeURIComponent(item.albumart) + "'>");
            } else {
                str.push("<div class='trackno'>" + i + "</div>");
            }
            str.push("<div><p class='title'>" + item.title + "</p>");
                str.push("<p class='artist'>" + item.artist + "</p>");
                str.push("<p class='description'>" + item.desc + "</p>");
            str.push("</div>");
        str.push("</li>");
    }

    str.push("</ul>");
    updateText("music", str.join(""));
}
