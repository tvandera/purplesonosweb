use strict;
use warnings;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::HTTP') };

can_ok('Sonos::HTTP', qw(registerHandler validateRequest validateAction));
