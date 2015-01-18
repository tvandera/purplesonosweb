/* Sample Sonos JS App. 
 * sonos.js must be included before this file
 *
 * It makes some big assumptions how things will be done.
 * Of course you don't have to use this to write your app.
 *
 */

var app = {};

function startspin() {
  $("#tabs").spin();
}

function stopspin() {
  $("#tabs").spin(false);
}

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

function mZones() {
    $("#top-labels").hide();
    $("#zone-container").show();
    $("#music").hide();
    $("#now-playing").hide();
    $("#queue").hide();
}

function mNowPlaying() {
    $("#top-labels").show();
    $("#zone-container").hide();
    $("#music").hide();
    $("#now-playing").show();
    $("#queue").hide();

    $("#currentzonename").show();
    $("#nowplayinglabel").hide();
    $("#musiclabel").show();
}

function mQueue() {
    $("#top-labels").show();
    $("#zone-container").hide();
    $("#music").hide();
    $("#now-playing").hide();
    $("#queue").show();

    $("#currentzonename").show();
    $("#nowplayinglabel").show();
    $("#musiclabel").hide();
}

function mMusic() {
    $("#top-labels").show();
    $("#zone-container").hide();
    $("#music").show();
    $("#now-playing").hide();
    $("#queue").hide();

    $("#currentzonename").show();
    $("#nowplayinglabel").show();
    $("#musiclabel").hide();
}

function start() {
    app.currentMusicPath = "";
    app.rootLastUpdate = 0;
    sonos.start();
}

function setCurrentZone(zoneId) {
    app.currentZoneId = zoneId;
    drawControl(zoneId);
    drawQueue(zoneId);
    drawZones();
    mNowPlaying();
}

function needZone() {
    if (!app.currentZoneId) {
        alert("Please select a Zone first.");
        return 1;
    }
    return 0
}

function doAction(action) {
    if (needZone()) return;
    sonos.sendControlAction(app.currentZoneId, action);
}

function doQAction(action, id) {
    if (needZone()) return;
    sonos.sendQueueAction(app.currentZoneId, action, id);
}

function doMAction(action, path) {
    if (needZone()) return;
    sonos.sendMusicAction(app.currentZoneId, action, path);
}

function browseTo(path) {
    if (needZone()) return;

    app.currentMusicPath = path;

    if (sonos.music[app.currentMusicPath]) {
        drawMusic(app.currentMusicPath);
    } else {
        sonos.sendMusicAction(app.currentZoneId, "Browse", app.currentMusicPath);
    }
}

function doLink(zone) {
    sonos.sendAction(app.currentZoneId, "Link", "&link="+zone);
}

function doUnlink(zone) {
    sonos.sendAction(app.currentZoneId, "Unlink", "&link="+zone);
}

function drawZones() {
    var str = "<ul>";
    i = 0;
    for (z in sonos.zones) {
        var zone = sonos.zones[z];
        if (app.currentZoneId == zone.ZONE_ID) str += "<B>";

        if (!zone.ZONE_LINKED && (i != 0)) str+= "</ul><ul>";

        str += "<li style='background-image: url(zone_icons/" + zone.ZONE_ICON + ".png);'>";
        str += "<A HREF=\"#\" onClick=\"setCurrentZone('" + zone.ZONE_ID + "')\">" + zone.ZONE_NAME + "</A>";
        
        if (zone.ZONE_LINKED) {
            str += " <a class=ulink href=\"#\" onClick=\"doUnlink('"+zone.ZONE_ID+"')\">[U]</a>";
        } else if (app.currentZoneId && app.currentZoneId != zone.ZONE_ID) {
            str += " <a class=ulink href=\"#\" onClick=\"doLink('"+zone.ZONE_ID+"')\">[L]</a></font>";
        }

        str += "</li>\n";

        if (app.currentZoneId == zone.ZONE_ID) str += "</B>";

        i++;
    }
    str += "</ul>";
    updateText("zones", str);
}

function drawControl(zoneId) {
    var info =  sonos.zones[app.currentZoneId];

    var fancyName = info.ZONE_NAME;
    if (info.ZONE_NUMLINKED > 0) fancyName += ' + ' + info.ZONE_NUMLINKED;

    $("a[href=info-container]").text(fancyName);
    updateText('currentzonename', fancyName);
    updateText('song', info.ACTIVE_NAME);
    updateText('album', info.ACTIVE_ALBUM);
    updateText('artist', info.ACTIVE_ARTIST);
    updateToggle("pause", "play", info.ACTIVE_MODE == 1);
    updateToggle("muteoff", "muteon", info.ACTIVE_MUTED);
    $("#volume").simpleSlider("setValue", info.ACTIVE_VOLUME);
    // $("#volume").prop("value", info.ACTIVE_VOLUME);
    updateSrc('albumart', info.ACTIVE_ALBUMART);
}

function drawQueue() {
    if (!sonos.queue) return;

    var str = new Array();
    str.push("<ul>");
    for (i=0; i < sonos.queue.length; i++) {
        var item = sonos.queue[i];
        //str.push("<li onClick=\"doQAction('Seek', '" + item.id + "'>");
        str.push("<li onClick='$(this).find(\".buttons\").toggle()'>");
        str.push("<img class='albumart' src='" + item.QUEUE_ALBUMART + "'>");
        str.push("<div><p class='title'>" + item.QUEUE_NAME + "</p>");
        str.push("<p class='artist'>" + item.QUEUE_ARTIST + "</p>");
        str.push("<p class='buttons'>");
        str.push("<A HREF=\"#\" onClick=\"doQAction('Remove', '" + item.QUEUE_ID + "')\">Remove</A>");
        str.push(" - <A HREF=\"#\" onClick=\"doQAction('Seek', '" + item.QUEUE_ID + "')\">Seek</A>");
        str.push("</p>");
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
    str.push("<ul>");
    if (path != "") {
        str.push("<li class='header'>");
        parent_path = decodeURIComponent(info.MUSIC_PARENT); 
        str.push("<img onClick='browseTo(\"" + parent_path + "\")' src='tiles/back.svg'>");
        str.push("<div><p id='musicpath'>" + info.MUSIC_NAME + "</p>");
        if (info.MUSIC_ARTIST) str.push("<p class='artist'>" + info.MUSIC_ARTIST + "</p>");
        str.push("<p class='buttons'><a HREF='#' onClick='doMAction(\"PlayMusic\", \"" + path + "\");'>Play</A> - <a HREF='#' onClick='doMAction(\"AddMusic\", \"" + path + "\");'>Add</A></p>");
        str.push("</div></li>");

        if (info.MUSIC_ALBUMART && info.MUSIC_CLASS == "object.container.album.musicAlbum") {
            str.push("<li class='albumart'><img onerror='this.src=\"tiles/missingaa_lite.svg\";' src='" + info.MUSIC_ALBUMART + "'></li>");
        }
    }
  
    // container items
    for (i=0; i < info.MUSIC_LOOP.length; i++) {
        var item = info.MUSIC_LOOP[i];
        path = decodeURIComponent(item.MUSIC_PATH); 
        str.push("<li onClick='browseTo(\"" + path + "\")'>");
        if (item.MUSIC_ALBUMART && ! (info.MUSIC_ALBUMART && info.MUSIC_CLASS == "object.container.album.musicAlbum")) { 
            str.push("<img onerror='this.src=\"tiles/missingaa_dark.svg\";' src='" + decodeURIComponent(item.MUSIC_ALBUMART) + "'>");
        } else {
            str.push("<div class='trackno'>" + i + "</div>");
        }

        str.push("<div><p class='title'>" + item.MUSIC_NAME + "</p>");
        if (item.MUSIC_ARTIST && item.MUSIC_ARTIST != info.MUSIC_ARTIST)
            str.push("<p class='artist'>" + item.MUSIC_ARTIST + "</p>");
        str.push("</div>");
        str.push("</li>");
    }

    str.push("</ul>");
    updateText("music", str.join(""));
}
