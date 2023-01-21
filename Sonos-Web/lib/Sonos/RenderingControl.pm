package Sonos::RenderingControl;

use base 'Sonos::Service';

use v5.36;
use strict;
use warnings;

sub info($self) {
}

# handled in base class
sub processUpdate {
    my $self = shift;
    $self->processStateUpdate(@_);
}

1;