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
my $daemon = Sonos::HTTP->new($loop, $discover, LocalAddr => '0.0.0.0', LocalPort => 8080);

$SIG{INT} = sub {
    print STDERR "Ctrl-C - stopping in 1 sec\n";
    sleep(1);
    $loop->stop();
};

$loop->run;