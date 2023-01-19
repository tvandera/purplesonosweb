package Sonos::Service;

use v5.36;
use strict;
use warnings;

use constant SERVICE_PREFIX => "urn:schemas-upnp-org:service:";
use constant SERVICE_SUFFIX => ":1";


use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;

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

# service name == class name
sub shortName($self) {
    return ref $self;
}

sub fullName($self) {
    SERVICE_PREFIX . $self->shortName() . SERVICE_SUFFIX;
}

sub getPlayer($self) {
    return $self->{_player};
}

sub populated($self) {
    return $self->{_state};
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



sub findValue($val) {
    return $val unless ref($val) eq 'HASH';
    return $val->{val} if defined $val->{val};
    return $val->{item} if defined $val->{item};

    while (my ($key, $value) = each %$val) {
        $val->{$key} = findValue($value);
    }

    return $val;
}

# called when rendering properties (like volume) are changed
# called when 'currently-playing' has changed
sub processStateUpdate ( $self, $service, %properties ) {
    INFO "StateUpdate for " . Dumper($service);
    my $tree = XMLin(
        decode_entities( $properties{LastChange} ),
        forcearray => ["ZoneGroup"],
        keyattr    => {
            "Volume"   => "channel",
            "Mute"     => "channel",
            "Loudness" => "channel"
        }
    );
    my %instancedata = %{ $tree->{InstanceID} };

    # many of these propoerties are XML html-encodeded
    # entities. Decode + parse XML + extract "val" attr
    foreach my $key ( keys %instancedata ) {
        my $val = $instancedata{$key};
        $val = findValue($val);
        $val = decode_entities($val) if ( $val =~ /^&lt;/ );
        $val = \%{ XMLin($val) }     if ( $val =~ /^</ );
        $val = findValue($val);
        $instancedata{$key} = $val
    }


    # merge new _state into existing
    %{$self->{_state}} = ( %{$self->{_state}}, %instancedata);

    $self->deviceInfo();
}

1;
