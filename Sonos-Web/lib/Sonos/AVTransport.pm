package Sonos::AVTransport;

use base 'Sonos::Service';

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);


sub info($self) {
}

# handled in base class
sub processUpdate {
    my $self = shift;
    $self->processStateUpdate(@_);
}

1;