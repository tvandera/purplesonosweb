use strict;
use warnings;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::UPnP') };

ok(Sonos::UPnP->new());

my $client = Sonos::UPnP->new();
sleep();