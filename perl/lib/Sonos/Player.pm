package Sonos::Player;

use v5.36;
use strict;
use warnings;

use List::Util qw( all max );

require UPnP::ControlPoint;

use XML::Liberal ();
XML::Liberal->globally_override('LibXML');

use URI::Escape qw( uri_escape_utf8 );

require Sonos::Player::ZoneGroupTopology;
require Sonos::Player::ContentDirectory;
require Sonos::Player::AVTransport;
require Sonos::Player::RenderingControl;

use constant SERVICE_TYPE => "urn:schemas-upnp-org:device:ZonePlayer:1";

use constant SERVICE_NAMES => (
    "ZoneGroupTopology",    # zones
    "ContentDirectory",     # music library
    "AVTransport",          # currently playing track
    "RenderingControl",     # volume etc
    "Queue",                # queue
);

sub new {
    my ( $self, $upnp, $system, %args ) = @_;
    my $class = ref($self) || $self;

    $self = bless {
        _upnp      => $upnp,
        _system    => $system,
        _services  => {},
        _callbacks => [],
    }, $class;

    for my $name (SERVICE_NAMES) {
        my $classname = "Sonos::Player::$name";
        $self->{_services}->{$name} = $classname->new($self);
    }

    return $self;
}

sub populated($self) {
    return all { $_->populated() } values %{ $self->{_services} };
}

sub lastUpdate($self) {
    my @values = map { $_->lastUpdate() } values %{ $self->{_services} };
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

sub cmp( $a, $b ) {
    return

      # sort by zoneGroup coordinator
      fc( $a->zoneGroupTopology()->coordinator()->friendlyName() ) cmp
      fc( $b->zoneGroupTopology()->coordinator()->friendlyName() )
      ||

      # then put coordinator first
      ( $b->zoneGroupTopology()->isCoordinator() )
      ||

      # then sort by zonename
      fc( $a->friendlyName() ) cmp fc( $b->friendlyName() );
}

sub services($self) {
    return values %{ $self->{_services} };
}

# Sonos::Service object for given name
sub getService( $self, $name ) {
    return $self->{_services}->{$name};
}

sub system($self) {
    return $self->{_system};
}

# UPnP::ControlPoint object
sub getUPnP($self) {
    return $self->{_upnp};
}

sub log( $self, @args ) {
    $self->system()->log( $self->friendlyName, @args );
}

# -- methods for the different services --

sub zoneGroupTopology($self) { return $self->getService("ZoneGroupTopology"); }
sub renderingControl($self)  { return $self->getService("RenderingControl"); }
sub avTransport($self)       { return $self->getService("AVTransport"); }
sub contentDirectory($self)  { return $self->getService("ContentDirectory"); }
sub queue($self)             { return $self->getService("Queue"); }

sub TO_JSON( $self, $isactive = 0 ) {
    return {
        "id"          => $self->UDN(),
        "arg"         => "zone=" . uri_escape_utf8( $self->zoneName() ) . "&",
        "name"        => $self->zoneName(),
        "isactive"    => Types::Serialiser::as_bool($isactive),
        "last_update" => $self->lastUpdate(),
        "zone"        => $self->zoneGroupTopology()->TO_JSON(),
        "av"          => $self->avTransport()->TO_JSON(),
        "render"      => $self->renderingControl()->TO_JSON(),
        "queue"       => $self->queue()->TO_JSON()
    };
}

sub onUpdate( $self, $callback ) {
    push @{ $self->{_callbacks} }, $callback;
}

sub doCallBacks($self) {
    $_->($self) for @{ $self->{_callbacks} };
    $self->{_callbacks} = [];

    # we also have callbacks at system level
    # whenever something in any of the services has changed
    $self->system()->doCallBacks();
}
