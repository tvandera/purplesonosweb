use strict;
use warnings;

use IO::Async::Loop::Select;
use Test::More tests => 3;

BEGIN { use_ok('Sonos::System') };

my $loop = IO::Async::Loop::Select->new;
my $system = bless {
   _controlpoint => bless({}, 'Local::ControlPoint'),
   _players      => {},
}, 'Sonos::System';

$system->addToLoop($loop);
is($system->loop(), $loop, 'attaches the system to the async loop');
is($system->numPlayers(), 0, 'starts without discovered players');

package Local::ControlPoint;
sub sockets { return; }
