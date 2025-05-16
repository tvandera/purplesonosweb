package Sonos::Player::Service;

use v5.36;
use strict;
use warnings;

use Carp qw( carp );

use constant SERVICE_PREFIX => "urn:schemas-upnp-org:service:";
use constant SERVICE_SUFFIX => ":1";

use IO::Async::Timer::Periodic ();

use XML::Liberal        ();
use XML::LibXML::Simple qw( XMLin );
XML::Liberal->globally_override('LibXML');

use HTML::Entities qw( decode_entities );

sub new {
    my ( $self, $player ) = @_;
    my $class = ref($self) || $self;

    $self = bless {
        _player       => $player,
        _subscription => undef,
        _state        => {},
        _callbacks    => [],
    }, $class;

    $self->renewSubscription();

    my $timer = IO::Async::Timer::Periodic->new(
        interval => 1800,    # renew subscription every 30 minutes
        on_tick  => sub { $self->renewSubscription(); },
    );
    $timer->start;

    $self->system()->loop()->add($timer);

    return $self;
}

sub getSubscription($self) {
    return $self->{_subscription};
}

sub friendlyName($self) {
    return $self->shortName() . "@" . $self->player()->friendlyName();
}

sub renewSubscription($self) {
    my $sub = $self->getSubscription();
    if ( defined $sub ) {
        $sub = $sub->renew();
    }

    # if the above failed, try to subscribe again
    if ( !$sub || $sub->expired() ) {
        my $service = $self->getUPnP();
        $self->{_subscription} =
          $service->subscribe( sub { $self->processUpdate(@_); } )
          or carp( "Could not subscribe to \"" . $self->fullName() . "\"" );
    }

   # add_timeout( time() + $main::RENEW_SUB_TIME, \&sonos_renew_subscriptions );

    return $self->getSubscription();
}

# service name == last part of class name
sub shortName($self) {
    my $full_classname = ref $self;    # e.g. Sonos::Player::AVTransport
    my @parts          = split /::/, $full_classname;
    return $parts[-1];                 # only take the AVTransport part
}

sub fullName($self) {
    SERVICE_PREFIX . $self->shortName() . SERVICE_SUFFIX;
}

sub lastUpdate($self) {
    return $self->{_state}->{LASTUPDATE} || -1;
}

sub lastUpdateReadable($self) {
    return localtime $self->{_state}->{LASTUPDATE} || "Unknown";
}

sub player($self) {
    return $self->{_player};
}

sub system($self) {
    return $self->player()->{_system};
}

sub musicLibrary($self) {
    return $self->system()->musicLibrary();
}

sub baseURL($self) {
    return $self->player()->location();
}

sub log( $self, @args ) {
    $self->player()->log(@args);
}

sub populated($self) {
    my $not_empty = keys %{ $self->{_state} };
    return $not_empty;
}

sub prop( $self, $path, $type = undef ) {
    my @path  = split "/", $path;
    my $value = $self->{_state};
    for (@path) {
        if ( ref $value eq 'HASH' and defined $value->{$_} ) {
            $value = $value->{$_};
        }
        else {
            return;
        }
    }

    return $value unless $type;
    return int($value)     if $type eq "int";
    return int( !!$value ) if $type eq "bool";

    carp "Unknown type: $type";
    return $value;
}

sub getUPnP($self) {
    my $fullname = $self->fullName();
    my $device   = $self->player()->getUPnP();

    my $service = $device->getService($fullname);
    return $service if $service;

    for my $child ( $device->children ) {
        $service = $child->getService($fullname);
        return $service if ($service);
    }

    die( "Could not find service: " . $self->fullName() );
    return;
}

sub controlProxy($self) {
    return $self->getUPnP->controlProxy;
}

sub action( $self, $action, @args ) {
    return $self->controlProxy()->$action( "0", @args );
}

sub onUpdate( $self, $callback ) {
    push @{ $self->{_callbacks} }, $callback;
}

sub doCallBacks($self) {
    $_->($self) for @{ $self->{_callbacks} };
    $self->{_callbacks} = [];

    # we also have callbacks at player level
    # whenever something in any of the services has changed
    $self->player()->doCallBacks();
}

sub DESTROY($self) {
    $self->getSubscription()->unsubscribe if defined $self->getSubscription();
}

# many of these properties are XML html-encoded entities.
# So we:
# - decode
# - parse XML
# - remove extra "val" and "item" attr
# - convert {} to ""
sub derefHelper($elem) {
    $elem = decode_entities($elem) if ( $elem =~ /^&lt;/ );
    $elem = \%{ XMLin($elem) }     if ( $elem =~ /^</ );

    # not a hashref -> itself
    return $elem unless ref($elem) eq 'HASH';

    # empty hashref -> ""
    my $num = scalar %{$elem};
    return "" if $num == 0;

    return derefHelper( $elem->{val} )  if defined $elem->{val} and $num == 1;
    return derefHelper( $elem->{item} ) if defined $elem->{item};
    return derefHelper( $elem->{"DIDL-Lite"} ) if defined $elem->{"DIDL-Lite"};

    while ( my ( $key, $val ) = each %$elem ) {
        $elem->{$key} = derefHelper($val);
    }

    return $elem;
}

# called when rendering properties (like volume) are changed
# called when 'currently-playing' has changed
sub processUpdateLastChange( $self, $service, %properties ) {
    return unless exists $properties{LastChange};

    my $tree = XMLin(
        decode_entities( $properties{LastChange} ),
        forcearray => ["ZoneGroup"],
        keyattr    => {
            "Volume"   => "channel",
            "Mute"     => "channel",
            "Loudness" => "channel"
        }
    );

    my $instancedata = derefHelper( $tree->{InstanceID} );

    # merge new _state into existing
    %{ $self->{_state} } = ( %{ $self->{_state} }, %{$instancedata} );
}

sub processUpdate ( $self, $service, %properties ) {

    $self->{_state}->{LASTUPDATE} = time;

    $self->doCallBacks();

    $self->info();
}

1;
