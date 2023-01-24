use v5.36;
use strict;
use warnings;

require IO::Async::Handle;
require IO::Async::Loop::Select;

require Sonos::Discovery;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;

my $loop = IO::Async::Loop::Select->new;
my $client = Sonos::Discovery->new($loop);

$SIG{INT} = sub {
    undef $client;
    undef $loop;
    exit 0;
};

$loop->run;