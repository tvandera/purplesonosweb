package Sonos::Service;

use v5.36;
use strict;
use warnings;

use constant SERVICE_PREFIX => "urn:schemas-upnp-org:service:";
use constant SERVICE_SUFFIX => ":1";


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
        $self->{_subscription} = $service->subscribe( sub { $self->update(@_); }  ) or
            carp("Could not subscribe to \"$name\"");
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

sub DESTROY($self)
{
    $self->getSubscription()->unsubscribe if defined $self->getSubscription();
}
