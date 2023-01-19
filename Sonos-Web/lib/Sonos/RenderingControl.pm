package Sonos::RenderingControl;

use base 'Sonos::Service';

use v5.36;
use strict;
use warnings;

sub new {
    my($self, $upnp, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _upnp => $upnp,
    }, $class;

    return $self;
}

sub info($self) {
}

# handled in base class
sub processUpdate {
    processStateUpdate(@_);
}

1;