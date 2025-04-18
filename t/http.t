use v5.36;
use strict;
use warnings;

use Test::More tests => 1;
require IO::Async::Loop::Select;
use IO::Async::Test;
require Sonos::HTTP;

my $loop = IO::Async::Loop::Select->new;
testing_loop( $loop );

my $daemon = Sonos::HTTP->new($loop, undef, LocalPort => 8080);
my $status;

$loop->spawn_child(
   code => sub {
      use LWP::UserAgent;
      my $useragent = LWP::UserAgent->new();
      my $response = $useragent->get($daemon->baseURL());
      return 1;
   },

   on_exit => sub {
      my ( $pid, $exitcode, $dollarbang, $dollarat ) = @_;
      $status = ( $exitcode >> 8 );
      print "Child process exited with status $status\n";
      print " OS error was $dollarbang, exception was $dollarat\n";
   },
);

wait_for { defined $status };