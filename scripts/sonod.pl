#!/usr/bin/env perl

use v5.36;
use strict;
use warnings;

use Carp;
$SIG{__DIE__} = \&Carp::confess;

require IO::Async::Loop::Select;
require Sonos::System;
require Sonos::HTTP;

use Log::Log4perl qw(:easy);
use Getopt::Long;

Log::Log4perl->easy_init($DEBUG);
binmode STDERR, ":encoding(UTF-8)";

# --- Default Configuration ---
my $default_local_addr = '0.0.0.0';
my $default_local_port = 9999;
my @default_locations = (
    'http://192.168.2.101:1400/xml/device_description.xml',
    'http://192.168.2.199:1400/xml/device_description.xml',
);

# --- Command Line Options ---
my $local_addr = $default_local_addr;
my $local_port = $default_local_port;
my @cli_locations;

GetOptions(
    'ip=s'        => \$local_addr,
    'port=i'      => \$local_port,
    'location=s@' => \@cli_locations, # Use @ to collect multiple --location flags
) or die "Error in command line arguments.\n";

my @locations_to_use = @cli_locations ? @cli_locations : @default_locations;

my $loop = IO::Async::Loop::Select->new;
my $system = Sonos::System->discover($loop, @locations_to_use);
my $daemon = Sonos::HTTP->new($loop, $system, LocalAddr => $local_addr, LocalPort => $local_port);

$SIG{INT} = sub {
    print STDERR "Ctrl-C - stopping\n";
    $loop->stop();
} unless ref $SIG{INT}; # do not overwrite SIG{INT}

$loop->run;