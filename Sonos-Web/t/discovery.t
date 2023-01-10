use strict;
use warnings;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::Discovery') };

ok(Sonos::Discovery->new());

my $client = Sonos::Discovery->new();
sleep();