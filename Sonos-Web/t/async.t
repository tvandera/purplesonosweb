use strict;
use warnings;

use Carp;

require IO::Async::Handle;
require IO::Async::Loop::Select;

require Sonos::Discovery;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;

my $loop = IO::Async::Loop::Select->new;
my $client = Sonos::Discovery->new();
my @selsockets = $client->sockets();

for my $socket (@selsockets) {
    my $handle = IO::Async::Handle->new(
        handle => $socket,
        on_read_ready => sub {
            $client->controlPoint()->handleOnce($socket);
        },
        on_write_ready => sub { carp },
    );

    $loop->add( $handle );
}

$loop->run;