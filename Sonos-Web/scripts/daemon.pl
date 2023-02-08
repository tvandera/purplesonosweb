use v5.36;
use strict;
use warnings;

use Carp;
$SIG{__DIE__} = \&Carp::confess;

require IO::Async::Handle;
require IO::Async::Loop::Select;
use IO::Async::Timer::Periodic;

require Sonos::Discovery;
require Sonos::HTTP;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;

my $loop = IO::Async::Loop::Select->new;
my $discover = Sonos::Discovery->new($loop);
my $daemon = Sonos::HTTP->new($loop, $discover, LocalAddr => UPnP::Common::getLocalIPAddress(), LocalPort => 9999);

print STDERR "\$SIG{INT} = " . $SIG{INT} . "\n";
$SIG{INT} = sub {
    print STDERR "Ctrl-C - stopping\n";
    $loop->stop();
} unless ref $SIG{INT};

$loop->run;