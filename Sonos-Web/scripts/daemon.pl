#!/usr/bin/env perl

use v5.36;
use strict;
use warnings;

use Carp;
$SIG{__DIE__} = \&Carp::confess;

require IO::Async::Handle;
require IO::Async::Loop::Select;
use IO::Async::Timer::Periodic;

require Sonos::System;
require Sonos::HTTP;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
binmode STDERR, ":encoding(UTF-8)";

use Data::Dumper;


my @locations = (
    'http://192.168.2.100:1400/xml/device_description.xml',
    'http://192.168.2.198:1400/xml/device_description.xml',
);

my $loop = IO::Async::Loop::Select->new;
my $system = Sonos::System->discover($loop, @locations);
my $daemon = Sonos::HTTP->new($loop, $system, LocalAddr => '0.0.0.0', LocalPort => 9999);

$SIG{INT} = sub {
    print STDERR "Ctrl-C - stopping\n";
    $loop->stop();
} unless ref $SIG{INT}; # do not overwrite SIG{INT}

$loop->run;