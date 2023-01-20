package Sonos::AVTransport;

use base 'Sonos::Service';

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

use HTML::Entities;

use Data::Dumper;
use Carp;

sub info($self) {
}

# handled in base class
sub processUpdate {
    processStateUpdate(@_);
}

1;