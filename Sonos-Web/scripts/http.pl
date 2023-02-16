use v5.36;
use strict;
use warnings;

use Carp;
$SIG{__DIE__} = \&Carp::confess;

require IO::Async::Loop::Select;

require Sonos::HTTP;

my $loop = IO::Async::Loop::Select->new;
my $discover = undef;
my $daemon = Sonos::HTTP->new($loop, $discover, LocalAddr => '0.0.0.0', LocalPort => 9999);

$SIG{INT} = sub {
    print STDERR "Ctrl-C - stopping\n";
    $loop->stop();
} unless ref $SIG{INT};

$loop->run;