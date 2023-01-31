package Sonos::Player::Service;

use v5.36;
use strict;
use warnings;

use constant SERVICE_PREFIX => "urn:schemas-upnp-org:service:";
use constant SERVICE_SUFFIX => ":1";

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

use HTML::Entities;

use Data::Dumper;
use Carp;

sub new {
    my($self, $player) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _player => $player,
        _subscription => undef,
        _state => {},
    }, $class;

    $self->renewSubscription();

    return $self;
}

sub getSubscription($self) {
    return $self->{_subscription};
}

sub friendlyName($self) {
    return $self->shortName() . "@" . $self->getPlayer()->friendlyName()
}

sub renewSubscription($self) {
    my $sub = $self->getSubscription();
    if (defined $sub) {
        $sub->renew();
    } else {
        my $service = $self->getUPnP();
        $self->{_subscription} = $service->subscribe( sub { $self->processUpdate(@_); }  ) or
            carp("Could not subscribe to \"" . $self->fullName() . "\"");
    }

    # add_timeout( time() + $main::RENEW_SUB_TIME, \&sonos_renew_subscriptions );

    return $self->getSubscription();
}

# service name == last part of class name
sub shortName($self) {
    my $full_classname = ref $self; # e.g. Sonos::Player::AVTransport
    my @parts = split /::/, $full_classname;
    return $parts[-1]; # only take the AVTransport part
}

sub fullName($self) {
    SERVICE_PREFIX . $self->shortName() . SERVICE_SUFFIX;
}

sub getPlayer($self) {
    return $self->{_player};
}

sub log($self, @args) {
    $self->getPlayer()->log(@args);
}

sub populated($self) {
    return $self->{_state};
}

sub prop($self, @path) {
    my $value = $self->{_state};
    for (@path) {
        if (ref $value eq 'HASH' and defined $value->{$_}) {
            $value = $value->{$_};
        } else {
            return undef;
        }
    }
    return $value;
}

sub getUPnP($self) {
    my $fullname = $self->fullName();
    my $device = $self->getPlayer()->getUPnP();

    my $service = $device->getService($fullname);
    return $service if $service;

   for my $child ( $device->children ) {
        $service = $child->getService($fullname);
        return $service if ($service);
    }

    carp("Could not find service: " . $self->fullName());
    return undef;
}

sub controlProxy($self) {
    return $self->getUPnP->controlProxy;
}

sub DESTROY($self)
{
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

    return derefHelper($elem->{val})  if defined $elem->{val} and $num == 1;
    return derefHelper($elem->{item}) if defined $elem->{item};

    while (my ($key, $val) = each %$elem) {

        $elem->{$key} = derefHelper($val);
    }

    return $elem;
}

# called when rendering properties (like volume) are changed
# called when 'currently-playing' has changed
sub processStateUpdate ( $self, $service, %properties ) {
    my $tree = XMLin(
        decode_entities( $properties{LastChange} ),
        forcearray => ["ZoneGroup"],
        keyattr    => {
            "Volume"   => "channel",
            "Mute"     => "channel",
            "Loudness" => "channel"
        }
    );


    my $instancedata = derefHelper($tree->{InstanceID});

    # merge new _state into existing
    %{$self->{_state}} = ( %{$self->{_state}}, %{$instancedata} );

    $self->info();
}

1;
