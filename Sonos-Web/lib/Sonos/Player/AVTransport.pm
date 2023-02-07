package Sonos::Player::AVTransport;

use base 'Sonos::Player::Service';

require Sonos::MetaData;

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;


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
sub curMetaData($self)   { return $self->isRadio() ? $self->curTransport() : $self->curTrack(); }

sub isRadio($self) {
    return $self->curTransport()->populated()
        && $self->curTransport()->isRadio();
}

sub info($self) {
    #DEBUG Dumper($self->{_state});
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

sub isPlaying($self) {
    return $self->transportState() eq "PLAYING";
}

sub isStopped($self) {
    return $self->transportState() eq "STOPPED";
}

sub startPlaying($self) {
    return $self->action("Play", "1");
}

sub stopPlaying($self) {
    return $self->action("Stop");
}

sub setURI( $self, $uri, $metadata ) {
    return $self->action( "SetAVTransportURI", $uri, $metadata );
}

sub addURI( $self, $uri, $metadata, $queueSlot ) {
    return $self->action( "AddURIToQueue", $uri, $metadata, $queueSlot );
}

sub standaloneCoordinator($self) {
    return $self->action( "BecomeCoordinatorOfStandaloneGroup",);
}

sub isRepeat($self) {
    return $self->currentPlayMode() =~ /^REPEAT/;
}

sub isShuffle($self) {
    return $self->currentPlayMode() =~ /^SHUFFLE/;
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
    return if $self->getRepeat() == $on_or_off;

    my %switch_repeat = (
        "NORMAL"  => "REPEAT_ALL",
        "SHUFFLE" => "SHUFFLE_NOREPEAT",
    );
    $self->switchPlayMode(%switch_repeat);
}


# if called with $on_or_off, sets shuffle mode to this value
# if called with $on_of_off == undef, switches shuffle mode
sub setShuffle($self, $on_or_off) {
    # nothing to do
    return if $self->getShuffle() == $on_or_off;

    my %switch_shuffle = (
        "NORMAL"     => "SHUFFLE_NOREPEAT",
        "REPEAT_ALL" => "SHUFFLE",
    );
    $self->switchPlayMode(%switch_shuffle);
}


# ---- queue ----

sub seek($self, $queue) {
    $queue =~ s,^.*/,,;
    return $self->action("Seek", "TRACK_NR", $queue );
}

sub removeTrackFromQueue($self, $objectid) {
    return $self->controlProxy()->RemoveTrackFromQueue( "0", $objectid );
}

1;