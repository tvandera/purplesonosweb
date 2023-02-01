use v5.36;
use strict;
use warnings;

use Carp;
$SIG{__DIE__} = \&Carp::confess;

require IO::Async::Handle;
require IO::Async::Loop::Select;
use IO::Async::Timer::Periodic;

require Sonos::Discovery;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;

my $loop = IO::Async::Loop::Select->new;
my $client = Sonos::Discovery->new($loop);

my $timer = IO::Async::Timer::Periodic->new(
   interval => 1,

   on_tick => sub {
        return unless $client->populated();
        print STDERR "All done.\n";
        my $sec = 5;
        while ($sec--) {
            printf "Stopping in %d seconds...\r", $sec;
            select()->flush();
            sleep 1
        }
        $loop->stop();
   },
)->start();

$loop->add($timer);

$loop->run;