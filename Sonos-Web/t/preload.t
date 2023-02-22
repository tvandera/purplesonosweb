use strict;
use warnings;

require IO::Select;

use Test::More tests => 2;

BEGIN { use_ok('Sonos::Discovery') };

my @locations = (
    'http://192.168.2.200:1400/xml/device_description.xml',
    'http://192.168.2.102:1400/xml/device_description.xml',
);

my $client = Sonos::Discovery->new(undef, @locations);
my @selsockets = $client->{_controlpoint}->sockets();
my $select = IO::Select->new(@selsockets);

while (1) {
    my @sockets = $select->can_read(5);
    map { $client->controlPoint()->handleOnce($_) } @sockets;
}