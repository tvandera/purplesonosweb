use strict;
use warnings;

use Log::Log4perl qw(:easy);
use Test::More tests => 2;

BEGIN { use_ok('Sonos::System') };
Log::Log4perl->easy_init($OFF);

my $client = bless { _players => { test => {} } }, 'Sonos::System';
my $device = {
    UDN         => 'uuid:test',
    FRIENDLYNAME => 'Test player',
    LOCATION    => 'http://player.test/device.xml',
};

$client->_discoveryCallback( undef, $device, 'deviceRemoved' );
is($client->numPlayers(), 0, 'removes a discovered player');
