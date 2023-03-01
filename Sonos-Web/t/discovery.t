use strict;
use warnings;

require IO::Select;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::System') };

my $client = Sonos::System->discover();
my @selsockets = $client->{_controlpoint}->sockets();
my $select = IO::Select->new(@selsockets);

while (1) {
    my @sockets = $select->can_read(5);
    map { $client->controlPoint()->handleOnce($_) } @sockets;
}