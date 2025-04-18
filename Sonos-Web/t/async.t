use strict;
use warnings;

use Carp;

require IO::Async::Handle;
require IO::Async::Timer::Periodic;
require IO::Async::Loop::Select;

require Sonos::System;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;

my $loop = IO::Async::Loop::Select->new;
my $client = Sonos::System->new($loop);

my $timer = IO::Async::Timer::Periodic->new(
   interval => 5,

   on_tick => sub {
        $loop->stop;
   },
);

$timer->start;

$loop->add($timer);

$loop->run;