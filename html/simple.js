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
    var name = zone_info.ACTIVE_NAME;
    if (!name && !zone_info.ACTIVE_ALBUM && !zone_info.ACTIVE_ARTIST)
        name = "<em>Not playing</em>";
    updateText('song', name);
    updateText('album', zone_info.ACTIVE_ALBUM);
    updateText('artist', zone_info.ACTIVE_ARTIST);
    updateToggle("pause", "play", zone_info.ACTIVE_MODE == 1);
    updateToggle("muteoff", "muteon", zone_info.ACTIVE_MUTED);
    updateText("volume", "" +  zone_info.ACTIVE_VOLUME + "%");
    var image = zone_info.ACTIVE_ALBUMART;
    if (!image) image = "tiles/missingaa_lite.svg";
    updateSrc('albumart', image);
}


function goto(base, extra) { 
    var url = base + '.html?' + zone_arg + music_arg; 
    if (typeof extra !== 'undefined') url += extra;
    window.location.href = url; 
}
function reload() {
    if (page() != "playing") return;

    var url = '/zone_data.html?action=Wait&' + zone_arg + 'lastupdate=' + last_update; 
    var r   = new XMLHttpRequest();
    r.open("GET",url,true);
    r.onreadystatechange = function() { if (r.readyState == 4) eval(r.responseText); }
    r.send();
}
function browse(music_arg) { window.location.href = 'music.html?' + zone_arg + music_arg + "&action=Browse"; }
function zone(name)   { window.location.href = 'playing.html?zone=' + name + "&" + music_arg; }

function send(cmd) {
  var url = '/action.html?NoWait=1&' + zone_arg + 'action=' + cmd;
  var r   = new XMLHttpRequest();
  r.open("GET",url,true);
  r.send();
}

function play(music_arg){ window.location.href = "playing.html?" + zone_arg + "action=PlayMusic&" + music_arg; }
function add(music_arg) { window.location.href = "playing.html?" + zone_arg + "action=AddMusic&" + music_arg; }


