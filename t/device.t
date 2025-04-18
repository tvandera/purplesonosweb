use strict;
use warnings;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::Player') };

my $client = Sonos::Player->new("http://192.168.2.200:1400/xml/device_description.xml");
