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

function mSelectLabel(name) {
    var labels = [ "currentzone", "nowplaying", "music", "queue" ];
    for (i=0; i < labels.length; i++) {
        var n = labels[i];
        if (name == n) $('#' + n + "label").css("background", "#666");
        else $('#' + n + "label").css("background", "#000");
    }
}


function mNowPlaying() {
    $("#top-labels").show();
    $("#zone-container").hide();
    $("#music").hide();
    $("#now-playing").show();
    $("#queue").hide();

    mSelectLabel("nowplaying");
}


function mQueue() {
    $("#top-labels").show();
    $("#zone-container").hide();
    $("#music").hide();
    $("#now-playing").hide();
    $("#queue").show();

    mSelectLabel("queue");
}

function mMusic() {
    $("#top-labels").show();
    $("#zone-container").hide();
    $("#music").show();
    $("#now-playing").hide();
    $("#queue").hide();

    mSelectLabel("music");
}

function start() {
    app.currentMusicPath = "";
    app.musicPathStack = [];
    app.rootLastUpdate = 0;
    sonos.start();
    mZones();
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

function browseBack() {
    if (app.musicPathStack.length == 0) return;
    browseTo(app.musicPathStack.pop(), true);
}

function browseTo(path,nobreadcrumbs) {
    if (needZone()) return;

    if (!nobreadcrumbs) app.musicPathStack.push(app.currentMusicPath);
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
    var str = "";
    for (i = 0; i<sonos.zones.length; i++) {
        var zone = sonos.zones[i];

        if (!zone.zone_linked) {
            if (i != 0) str+= "</ul>";
            str+= "<ul onClick=\"setCurrentZone('" + zone.zone_id + "')\">";
        }

        if (app.currentZoneId == zone.zone_id) str += "<b>";

        str += "<li style='background-image: url(zone_icons/" + zone.zone_icon + ".png);'>" + zone.zone_name;
        
        if (zone.zone_linked) {
            str += " <a class=ulink href=\"#\" onClick=\"doUnlink('"+zone.zone_id+"')\">[U]</a>";
        } else if (app.currentZoneId && app.currentZoneId != zone.zone_id) {
            str += " <a class=ulink href=\"#\" onClick=\"doLink('"+zone.zone_id+"')\">[L]</a></font>";
        }

        str += "</li>\n";

        if (app.currentZoneId == zone.zone_id) str += "</b>";
    }
    str += "</ul>";
    updateText("zones", str);
}

function curZoneInfo() {
    for (z in sonos.zones) {
        var zone = sonos.zones[z];
        if (zone.zone_id != app.currentZoneId) continue;
        return zone;
    }
}

function drawControl(zoneId) {
    if (zoneId != app.currentZoneId) return;
    var info = curZoneInfo();

    var fancyName = info.zone_name;
    if (info.ZONE_NUMLINKED > 0) fancyName += ' + ' + info.ZONE_NUMLINKED;

    $("a[href=info-container]").text(fancyName);
    updateText('currentzonename', fancyName);
    var name = info.active_name;
    if (!name && !info.active_album && !info.active_artist)
        name = "<em>Not playing</em>";
    updateText('song', name);
    updateText('album', info.active_album);
    updateText('artist', info.active_artist);
    updateToggle("pause", "play", info.active_mode == 1);
    updateToggle("muteoff", "muteon", info.active_muted);
    $("#volume").simpleSlider("setValue", info.active_volume);
    var image = info.active_albumart;
    if (!image) image = "tiles/missingaa_lite.svg";
    updateSrc('albumart', image);
    drawQueue(zoneId);
}

function drawQueue(zoneId) {
    if (zoneId != app.currentZoneId) return;
    if (!sonos.queues[zoneId]) return;
    var queue = sonos.queues[zoneId]; 
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
    } else for (i=0; i < queue.length; i++) {
        var item = queue[i];
        var paused = (cur_track == item.QUEUE_TRACK_NUM) && zone_paused;
        var playing = (cur_track == item.QUEUE_TRACK_NUM) && zone_playing;

        if (paused)       action = "doAction('Play');";
        else if (playing) action = "doAction('Pause');"
        else              action = "doQAction('Seek', '" + item.queue_id + "'); doAction('Play');";
        str.push("<li onClick=\"" + action + "\">");

        if (paused) img = 'svg/pause.svg';
        else if (playing) img = 'svg/pause.svg';
        else img = item.QUEUE_ALBUMART;
        str.push("<img class='albumart' src='" + img + "'>");

        str.push("<div><p class='title'>" + item.queue_name + "</p>");
        str.push("<p class='artist'>" + item.QUEUE_ARTIST + "</p>");
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
    if (path != "") {
        str.push("<li class='header'>");
        str.push("<img onClick='browseBack()' src='tiles/back.svg'>");
        str.push("<div><p id='musicpath'>" + info.music_name + "</p>");
        if (info.MUSIC_ARTIST) str.push("<p class='artist'>" + info.MUSIC_ARTIST + "</p>");
        if (info.MUSIC_CLASS == "object.container.album.musicAlbum") { 
            str.push("<p class='buttons'><a HREF='#' onClick='doMAction(\"PlayMusic\", \"" + path + "\");'>Play</A> - <a HREF='#' onClick='doMAction(\"AddMusic\", \"" + path + "\");'>Add</A></p>");
        }
        str.push("</div></li>");

        if (info.music_albumart && info.MUSIC_CLASS == "object.container.album.musicAlbum") {
            str.push("<li class='albumart'><img onerror='this.src=\"tiles/missingaa_lite.svg\";' src='" + info.music_albumart + "'></li>");
        }
    }
  
    // container items
    for (i=0; i < info.music_loop.length; i++) {
        var item = info.music_loop[i];
        path = decodeURIComponent(item.MUSIC_REALPATH); 
        str.push("<li");
        if (item.MUSIC_REALCLASS == "object.item.audioItem.audioBroadcast")
            str.push(" onClick='doMAction(\"PlayMusic\", \"" + path + "\");'>");
        else 
            str.push(" onClick='browseTo(\"" + path + "\")'>");

        if (item.music_albumart && ! (info.music_albumart && info.MUSIC_CLASS == "object.container.album.musicAlbum")) { 
            str.push("<img onerror='this.src=\"tiles/missingaa_dark.svg\";' src='" + decodeURIComponent(item.music_albumart) + "'>");
        } else {
            str.push("<div class='trackno'>" + i + "</div>");
        }

        str.push("<div><p class='title'>" + item.music_name + "</p>");
        if (item.MUSIC_ARTIST && item.MUSIC_ARTIST != info.MUSIC_ARTIST)
            str.push("<p class='artist'>" + item.MUSIC_ARTIST + "</p>");
        if (item.MUSIC_DESC)
            str.push("<p class='description'>" + item.MUSIC_DESC + "</p>");
        str.push("</div>");
        str.push("</li>");
    }

    str.push("</ul>");
    updateText("music", str.join(""));
    // $( '#musiclist' ).listview( 'refresh' ).alphascroll();
    
}
