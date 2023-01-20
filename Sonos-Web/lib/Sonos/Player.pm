package Sonos::Player;

use v5.36;
use strict;
use warnings;

require UPnP::ControlPoint;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

use HTML::Entities;

use Data::Dumper;
use Carp;

require Sonos::ZoneGroupTopology;
require Sonos::ContentDirectory;
require Sonos::AVTransport;
require Sonos::RenderingControl;

use constant SERVICE_TYPE => "urn:schemas-upnp-org:device:ZonePlayer:1";

use constant SERVICE_NAMES => (
    "ZoneGroupTopology", # zones
    "ContentDirectory",  # music library
    "AVTransport",       # currently playing track
    "RenderingControl"   # volume etc
);

sub new {
    my($self, $upnp, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _upnp => $upnp,
        _services => { },
    }, $class;

    for my $name (SERVICE_NAMES) {
        my $classname = "Sonos::$name";
        $self->{_services}->{$name} = $classname->new($self);
    }

    return $self;
}

sub getService($self, $name) {
    return $self->{_services}->{$name};
}

sub getUPnP($self) {
    return $self->{_upnp};
}

sub deviceInfo($self) {
    DEBUG Dumper($self);
}




# called when anything in ContentDirectory has been updated
# forward to _contentdirectory member
sub processContentDirectory ( $self, $service, %properties ) {
    # $self->{_contentdirectory}->processUpdate($service, %properties);
}

sub avTransportProxy($self) {
    return $self->getService("AVTransport")->controlProxy;
}

sub renderProxy($self) {
    return $self->getService("RenderingControl")->controlProxy;
}

sub removeTrackFromQueue($self, $objectid) {
    return $self->avTransportProxy()->RemoveTrackFromQueue( "0", $objectid );
}

sub startPlaying($self) {
    return $self->avTransportAction("Play", "1" );
}

sub seek($self, $queue) {
    $queue =~ s,^.*/,,;
    return $self->avTransportAction("Seek", "TRACK_NR", $queue );
}

sub getVolume($self) {
    return $self->{_state}->{Volume}->{Master};
}

sub setVolume($self, $value) {
    $self->renderAction("SetVolume", "Master", $value);
}

sub changeVolume($self, $diff) {
    my $vol = $self->getVolume() + $diff;
    $self->setVolume($vol);
}

sub avtransportAction( $self, $action, @args ) {
    return $self->avTransportProxy()->$action("0,", @args);
}

sub renderAction( $self, $action, @args ) {
    return $self->renderProxy()->$action("0", @args);
}

sub getRepeat($self) {
    return $self->{_state}->{CurrentPlayMode} =~ /^REPEAT/;
}

sub getShuffle($self) {
    return $self->{_state}->{CurrentPlayMode} =~ /^SHUFFLE/;
}

sub getMute($self) {
    return $self->{_state}->{Mute}->{Master};
}

sub setMute($self, $on_or_off) {
    return if $on_or_off == $self->getMute();
    return $self->renderAction("SetMute", "Master", $on_or_off)
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

sub setURI( $self, $uri, $metadata ) {
    return $self->avTransportAction( "SetAVTransportURI", $uri, $metadata );
}

sub addURI( $self, $uri, $metadata, $queueSlot ) {
    return $self->avTransportAction( "AddURIToQueue", $uri, $metadata, $queueSlot );
}

sub standaloneCoordinator($self) {
    return $self->avTransportAction( "BecomeCoordinatorOfStandaloneGroup",);
}


