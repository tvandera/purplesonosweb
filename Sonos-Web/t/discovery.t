use strict;
use warnings;

require IO::Select;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::Discovery') };

my $client = Sonos::Discovery->new();
my @selsockets = $client->{_controlpoint}->sockets();
my $select = IO::Select->new(@selsockets);

while ($client->numDevices() < 2) {
    my @sockets = $select->can_read(5);
    map { $client->controlPoint()->handleOnce($_) } @sockets;
}

pass("found 2 devices");
