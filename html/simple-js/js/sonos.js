// Public Functions
/* To use this script, 4 functions must be implemented
 *
 * drawZones()
 *    The available zones have changed.
 *    sonos.zones is an array of the zone ids
 *    sonos[zoneId] is an object with lots of info about the zone
 *
 * drawControl(zoneId)
 *    The control data for a zone has changed
 *    sonos[zoneId] is an object with lots of info about the zone
 *
 * drawQueue(zoneId)
 *    The queue for a zone has changed
 *    sonos[zoneId].queue is an array of objects with info about the
 *    items in the queue
 *
 * drawMusic(path)
 *    A Music query has returned, path is "*Search*" for searches.
 *    sonos.music[path].items is an array of objects with info about the
 *    music at the path location
 *
 */
"use strict";

var sonos = {};

sonos.start = function() {
    sonos.music = {};
    sonos._lastUpdate = 1;
    sonos.zones = {};
    sonos.queues = {};
    sonos._fetch();
}

sonos.sendAction = function(zoneId, action, other) {
    if (!other) other = "";
    sonos._loadData("/api?nowait=1&action=" + action + "&zone=" + zoneId + other);
}

sonos.sendControlAction = function(zoneId, action) {
    sonos.sendAction(zoneId, action);
}

sonos.sendSaveAction = function(zoneId, name) {
    sonos.sendAction(zoneId, "Save", "&savename=" + name);
}

sonos.sendQueueAction = function(zoneId, action, id) {
    sonos.sendAction(zoneId, action, "&queue=" + id);
}

sonos.sendMusicAction = function(zoneId, action, path) {
    sonos.sendAction(zoneId, action, "&mpath=" + encodeURIComponent(path));
}

sonos.sendMusicSearch = function(path) {
    sonos._loadData("/api?last_update="+sonos._lastUpdate + "&msearch=" + encodeURIComponent(path));
}

sonos.sendMusicBrowse = function(path) {
    sonos._loadData("/api?last_update="+sonos._lastUpdate + "&mpath=" + encodeURIComponent(path));
}

sonos.setVolume = function(zoneId, volume) {
    sonos.sendAction(zoneId, "SetVolume", "&volume=" + volume);
}

// Private Functions
sonos._loadData = function(filename, afterFunc) {
    console.log("sonos load: " + filename);
    Http.get(filename, function (data) {
        let all = JSON.parse(data);
        sonos.zones = all.players;
        sonos.music[all.music.id] = all.music;
        sonos.queues = all.player.queue;
        sonos._lastUpdate = all.last_update;
        if (afterFunc) eval(afterFunc);
        drawZones();
   });
}

sonos._doFetch = function() {
    sonos._loadData("/api?action=Wait&last_update="+sonos._lastUpdate, "sonos._fetch();");
}

sonos._fetch = function() {
    window.setTimeout("sonos._doFetch();", 100);
}