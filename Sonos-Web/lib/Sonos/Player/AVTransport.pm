package Sonos::Player::AVTransport;

use base 'Sonos::Player::Service';

require Sonos::MetaData;

use v5.36;
use strict;
use warnings;

# Global
sub transportState($self)       { return $self->prop("TransportState"); }
sub currentPlayMode($self)      { return $self->prop("CurrentPlayMode"); }
sub currentTrack($self)         { return $self->prop("CurrentTrack"); }
sub numberOfTracks($self)       { return $self->prop("NumberOfTracks"); }
sub currentTrackDuration($self) { return $self->prop("CurrentTrackDuration"); }
sub lengthInSeconds($self) {
    my $duration = $self->currentTrackDuration();
    my ($hours, $minutes, $seconds) = split(":", $duration);
    return $hours*3600 + $minutes*60 + $seconds;
}

sub nextTrack($self)     { return Sonos::MetaData->new($self->prop("r:NextTrackMetaData")); }
sub curTrack($self)      { return Sonos::MetaData->new($self->prop("CurrentTrackMetaData")); }
sub curTransport($self)  { return Sonos::MetaData->new($self->prop("AVTransportURIMetaData")); }

sub metaData($self) {
    return Sonos::MetaData->new(
        $self->prop("CurrentTrackMetaData"),
        $self->prop("AVTransportURIMetaData")
    );
}

sub isRadio($self) {
    return Sonos::MetaData::bool($self->curTransport()->populated()
        && $self->curTransport()->isRadio());
}

sub name($self) {
    return $self->isRadio()
        ? $self->curTransport()->title()
        : $self->curTrack()->title();
}

sub description($self) {
    return $self->isRadio()
        ? $self->curTransport()->streamContent()
        : $self->curTrack()->()->creator() . " / " . $self->curTrack()->album();
}

sub info($self) {
    my @fields = (
        "lastUpdateReadable",
        "transportState",
        "currentPlayMode",
    );

    $self->log($self->shortName(), ":");
    for (@fields) {
        my $value = $self->$_();
        $self->log("  " . $_ . ": " . $value) if defined $value;
    }
    for ( "curTrack", "curTransport", "nextTrack" ) {
        next unless $self->$_()->populated();
        $self->log("  $_:");
        $self->$_()->log($self, " " x 4);
    }

}

sub processUpdate {
    my $self = shift;
    $self->processUpdateLastChange(@_);
    $self->SUPER::processUpdate(@_)
}

sub stateIs($self, $value) {
    return int($self->transportState() eq $value);
}

sub isPlaying($self) { return $self->stateIs("PLAYING"); }
sub isPaused($self) { return $self->stateIs("PAUSED_PLAYBACK"); }
sub isStopped($self) { return $self->stateIs("STOPPED"); }

sub play($self) {
    return 0 if $self->isPlaying();
    return $self->action("Play", "1");
}

sub pause($self) {
    return 0 if $self->isPaused();
    return $self->action("Pause");
}

sub stop($self) {
    return 0 if $self->isStopped();
    return $self->action("Stop");
}

sub previous($self) {
    return $self->action("Previous");
}

sub next($self) {
    return $self->action("Next");
}


sub setURI( $self, $uri, $metadata ) {
    return $self->action( "SetAVTransportURI", $uri, $metadata );
}

sub setRadio( $self, $mpath) {
    my $entry = $self->musicLibrary()->item($mpath);

    die "Not radio: $mpath" unless $entry->isRadio();

# So, I'm very lazy :-)
    my $urimetadata = '&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;' . $entry->{id} . '&quot; parentID=&quot;' . $entry->{parentID} . '&quot; restricted=&quot;true&quot;&gt;&lt;dc:title&gt;'. $entry->{"dc:title"} .  '&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;&lt;desc id=&quot;cdudn&quot; nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;RINCON_AssociatedZPUDN&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;';

    $self->setURI($entry->content(), decode_entities($urimetadata));
}

sub setQueue($self) {
    my $id = $self->player()->UDN();
    $self->setURI("x-rincon-queue:" . $id . "#0", "");
}

sub addToQueue( $self, $mpath, $queueSlot = 0 ) {
    my $item = $self->musicLibrary()->item($mpath);
    my $uri = $item->content();
    my $metadata = "";
    return $self->action( "AddURIToQueue", $uri, $metadata, $queueSlot );
}

sub addURI( $self, $uri, $metadata = "", $queueSlot = 0 ) {
    $self->log("Add to queue: $uri");
}

sub standaloneCoordinator($self) {
    return $self->action( "BecomeCoordinatorOfStandaloneGroup",);
}

sub playModeMatches($self, $value) {
    return int($self->currentPlayMode() =~ /^$value/);
}

sub isRepeat($self) {
    return $self->playModeMatches("REPEAT");
}

sub isShuffle($self) {
    return $self->playModeMatches("SHUFFLE");
}

sub switchPlayMode($self, %switch_map) {
    my %map = (%switch_map, reverse %switch_map);
    my $new_playmode = $map{$self->currentPlayMode()};
    $self->action("SetPlayMode", $new_playmode)
}

# if called with $on_or_off, sets repeat mode to this value
# if called with $on_of_off == undef, switches repeat mode
sub setRepeat($self, $on_or_off) {
    # nothing to do if equal
    return 0 if $self->getRepeat() == $on_or_off;

    my %switch_repeat = (
        "NORMAL"  => "REPEAT_ALL",
        "SHUFFLE" => "SHUFFLE_NOREPEAT",
    );
    $self->switchPlayMode(%switch_repeat);

    return 1;
}

# if called with $on_or_off, sets shuffle mode to this value
# if called with $on_of_off == undef, switches shuffle mode
sub setShuffle($self, $on_or_off) {
    # nothing to do
    return 0 if $self->getShuffle() == $on_or_off;

    my %switch_shuffle = (
        "NORMAL"     => "SHUFFLE_NOREPEAT",
        "REPEAT_ALL" => "SHUFFLE",
    );
    $self->switchPlayMode(%switch_shuffle);

    return 1;
}

# ---- queue ----

sub seekInQueue($self, $queue) {
    $queue =~ s,^.*/,,;
    return $self->action("Seek", "TRACK_NR", $queue );
}

sub removeTrackFromQueue($self, $objectid) {
    return $self->action("RemoveTrackFromQueue", $objectid );
}

sub removeAllTracksFromQueue($self) {
    return $self->action("RemoveAllTracksFromQueue");
}


sub saveQueue($self, $name) {
    return $self->action("SaveQueue", $name, "" );
}

1;