# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl Sonos-Web.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::Config') };

can_ok('Sonos::Config', ( 'doconfig', 'readconfig' ))

