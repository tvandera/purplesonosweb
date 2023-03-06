package Sonos::Utils;

use v5.36;
use strict;
use warnings;


sub log($name, @args) {
    INFO sprintf("[%12s]: ", $name), @args;
}

1;