function page() {
    var path = window.location.pathname;
    var findex = path.lastIndexOf("/") + 1;
    var filename = path.substr(findex);
    var bindex = filename.lastIndexOf(".");
    var basename = filename.substr(0, bindex);
    return basename;
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

function drawControl() {
    if (page() != "playing") return;

    var info = "";
    if (zone_info.active_name) info += zone_info.active_name + '<br>';
    if (zone_info.active_album) {
      if (zone_info.active_isradio) info += "&nbsp;<em>station:</em> ";
      else info += "&nbsp;<em>album:</em> ";
      info += zone_info.active_album + '<br>';
    }
    if (zone_info.active_artist) info += "&nbsp;<em>artist:</em> " + zone_info.active_artist + '<br>';
    if (!info) info = "<em>Not playing</em>";
    updateText('info', info);

    updateToggle("pause", "play", zone_info.active_mode == 1);
    updateToggle("muteoff", "muteon", zone_info.active_muted);
    updateText("volume", "" +  zone_info.active_volume + "%");
    var image = zone_info.active_albumart;
    if (!image) image = "tiles/missingaa_lite.svg";
    updateSrc('albumart', image);

    update();
}


function goto(base, extra) {
    var url = base + '.html?' + zone_arg + music_arg;
    if (typeof extra !== 'undefined') url += extra;
    window.location.href = url;
}


function browse(music_arg) {window.location.href = 'music.html?' + zone_arg + music_arg + "&action=Browse"; }
function zone(name)   { window.location.href = 'playing.html?zone=' + name + "&" + music_arg; }

var zone_info = null;

function update() {
    if (page() != "playing") return;

    cmd = zone_info ? "Wait" : "None";
    r = send(
        cmd = cmd,
        what = "zone",
        onload = function() {
            zone_info = JSON.parse(this.responseText);
            last_update = zone_info.active_lastupdate;
            drawControl();
        }
    );
}

function send(cmd, what = "none", onload = null) {
    var nowait = onload ? "0" : "1";

    var url = '/api?what=' + what + '&nowait=' + nowait + '&' + zone_arg + 'action=' + cmd + '&lastupdate=' + last_update;
    var r = new XMLHttpRequest();
    r.open("GET", url, true);
    if (onload) r.onload = onload;
    r.send();

    return r;
}

function removeall() { window.location.href = "queue.html?" + zone_arg + "action=RemoveAll&" + music_arg; }
function seek(to) { window.location.href = "queue.html?" + zone_arg + "action=Seek&" + music_arg + to; }
function play(music_arg){ send("Play&" + music_arg); goto("playing"); }
function add(music_arg){ send("add&" + music_arg); goto("playing"); }

function softer() {
   send('MuchSofter');
   zone_info.active_volume -= 5;
   if (zone_info.active_volume < 0) zone_info.active_volume = 0;
   updateText("volume", "" +  zone_info.active_volume + "%");
}

function louder() {
   send('MuchLouder');
   zone_info.active_volume += 5;
   if (zone_info.active_volume > 100) zone_info.active_volume = 100;
   updateText("volume", "" +  zone_info.active_volume + "%");
}


