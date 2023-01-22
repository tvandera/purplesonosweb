use strict;
use warnings;

use Carp;

require IO::Async::Handle;
require IO::Async::Timer::Periodic;
require IO::Async::Loop::Select;

require Sonos::Discovery;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;

my $loop = IO::Async::Loop::Select->new;
my $client = Sonos::Discovery->new($loop);

my $timer = IO::Async::Timer::Periodic->new(
   interval => 5,

   on_tick => sub {
        my $player = ($client->players)[0];
        if ($player->isStopped()) {
            print STDERR $player->friendlyName() . " --> start playing\n";
            $player->startPlaying();
        } else {
            print STDERR $player->friendlyName() . " --> stop playing\n";
            $player->stopPlaying();
        }
   },
);

$timer->start;

$loop->add($timer);

$loop->run;