package Sonos::Utils;

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( { level => $DEBUG, utf8     => 1, });

sub log($name, @args) {
    INFO sprintf("[%12s]: ", $name), @args;
}

1;