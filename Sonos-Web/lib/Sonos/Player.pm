package Sonos::Player;

use v5.36;
use strict;
use warnings;

use List::Util qw(all max);

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
    "RenderingControl",  # volume etc
    "Queue",             # queue
);

sub new {
    my($self, $upnp, $discover, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _upnp => $upnp,
        _discovery => $discover,
        _services => { },
        _callbacks => [ ],
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

sub lastUpdate($self) {
    my @values = map { $_->lastUpdate() } values %{$self->{_services}};
    return max @values;
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

sub zoneName($self) {
    return $self->zoneGroupTopology()->zoneName();
}

sub services($self) {
    return values %{$self->{_services}};
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

# -- methods for the different services --

sub zoneGroupTopology($self) { return $self->getService("ZoneGroupTopology"); }
sub renderingControl($self)  { return $self->getService("RenderingControl"); }
sub avTransport($self)       { return $self->getService("AVTransport"); }
sub contentDirectory($self)  { return $self->getService("ContentDirectory"); }
sub queue($self)             { return $self->getService("Queue"); }


sub onUpdate($self, $callback) {
    push @{$self->{_callbacks}}, $callback;
}

sub doCallBacks($self) {
    $_->($self) for @{$self->{_callbacks}};
    $self->{_callbacks} = [];
}