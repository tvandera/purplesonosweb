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
 
var sonos = {};

sonos.start = function() {
    sonos.music = {};
    sonos._lastUpdate = 1;
    sonos._fetch();
    sonos.zones = {};
    sonos.queues = {};
}

sonos.sendAction = function(zoneId, action, other) {
    if (!other) other = "";
    startspin();
    sonos._loadData("/action.html?NoWait=1&action=" + action + "&zone=" + zoneId + other);
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

sonos.sendMusicSearch = function(zoneId, str) {
    sonos._loadData("/action.html?zone=" + zoneId + "&lastupdate="+sonos._lastUpdate + "&msearch="+str);
}

sonos.setVolume = function(zoneId, volume) {
    sonos.sendAction(zoneId, "SetVolume", "&volume=" + volume);
}

// Private Functions
sonos._loadData = function(filename, afterFunc) {
    console.log("sonos load: " + filename);
    Http.get(filename, function (data) {
        eval(data); 
        if (afterFunc) eval(afterFunc); 
   });
}

sonos._doFetch = function() {
    sonos._loadData("/data.html?action=Wait&lastupdate="+sonos._lastUpdate, "stopspin(); sonos._fetch();");
}

sonos._fetch = function() {
    window.setTimeout("sonos._doFetch();", 100);
}

sonos._setLastUpdate = function(lastUpdate) {
    sonos._lastUpdate = lastUpdate;
}

