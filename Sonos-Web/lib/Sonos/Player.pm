package Sonos::Player;

use v5.36;
use strict;
use warnings;

use List::Util "all";

require UPnP::ControlPoint;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

use HTML::Entities;

use Data::Dumper;
use Carp;

require Sonos::Player::ZoneGroupTopology;
require Sonos::Player::ContentDirectory;
require Sonos::Player::AVTransport;
require Sonos::Player::RenderingControl;

use constant SERVICE_TYPE => "urn:schemas-upnp-org:device:ZonePlayer:1";

use constant SERVICE_NAMES => (
    "ZoneGroupTopology", # zones
    "ContentDirectory",  # music library
    "AVTransport",       # currently playing track
    "RenderingControl"   # volume etc
);

sub new {
    my($self, $upnp, $discover, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _upnp => $upnp,
        _discovery => $discover,
        _services => { },
    }, $class;

    for my $name (SERVICE_NAMES) {
        my $classname = "Sonos::Player::$name";
        $self->{_services}->{$name} = $classname->new($self);
    }

    return $self;
}

sub populated($self) {
    return all { $_->populated() } values %{$self->{_services}};
}


# for Sonos this is smtg like RINCON_000E583472BC01400
# RINCON_<<MAC addresss>><<port>>
sub UDN($self) {
    my $uuid = $self->getUPnP()->UDN;
    $uuid =~ s/^uuid://g;
    return $uuid;
}

# http://192.168.x.y:1400/xml/device_description.xml
sub location($self) {
    return $self->getUPnP()->{LOCATION};
}


# "Living room" if defined or
# "192.168.x.y - Sonos Play:5"
sub friendlyName($self) {
    return $self->zoneName() if $self->zoneName;
    return $self->getUPnP()->{FRIENDLYNAME};
}

# info the zone associated with this player
sub zoneInfo($self) {
    return $self->getService("ZoneGroupTopology")->zoneInfo($self->UDN);
}

sub zoneName($self) {
    return undef if not $self->zoneInfo();
    return $self->zoneInfo()->{ZoneName};
}

# Sonos::Service object for given name
sub getService($self, $name) {
    return $self->{_services}->{$name};
}

# UPnP::ControlPoint object
sub getUPnP($self) {
    return $self->{_upnp};
}

sub log($self, @args) {
    INFO sprintf("[%12s]: ", $self->friendlyName), @args;
}


# -- AVTransport --

sub avTransportProxy($self) {
    return $self->getService("AVTransport")->controlProxy;
}

sub avTransportAction( $self, $action, @args ) {
    return $self->avTransportProxy()->$action("0,", @args);
}

sub isPlaying($self) {
    return $self->getService("AVTransport")->transportState() eq "PLAYING";
}

sub isStopped($self) {
    return $self->getService("AVTransport")->transportState() eq "STOPPED";
}

sub startPlaying($self) {
    return $self->avTransportAction("Play", "1");
}

sub stopPlaying($self) {
    return $self->avTransportAction("Stop");
}

sub setURI( $self, $uri, $metadata ) {
    return $self->avTransportAction( "SetAVTransportURI", $uri, $metadata );
}

sub addURI( $self, $uri, $metadata, $queueSlot ) {
    return $self->avTransportAction( "AddURIToQueue", $uri, $metadata, $queueSlot );
}

sub standaloneCoordinator($self) {
    return $self->avTransportAction( "BecomeCoordinatorOfStandaloneGroup",);
}

sub getRepeat($self) {
    return $self->{_state}->{CurrentPlayMode} =~ /^REPEAT/;
}

sub getShuffle($self) {
    return $self->{_state}->{CurrentPlayMode} =~ /^SHUFFLE/;
}

sub switchPlayMode($self, %switch_map) {
    my %map = (%switch_map, reverse %switch_map);
    my $new_playmode = $map{$self->GetPlayMode()};
    $self->avTransportAction("SetPlayMode", $new_playmode)
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
    return $self->avTransportAction("Seek", "TRACK_NR", $queue );
}

sub removeTrackFromQueue($self, $objectid) {
    return $self->avTransportProxy()->RemoveTrackFromQueue( "0", $objectid );
}

