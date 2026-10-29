use strict;
use warnings;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::Player') };

can_ok('Sonos::Player', qw(new services getService));
