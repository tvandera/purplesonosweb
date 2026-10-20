use v5.36;
use strict;
use warnings;

use Cwd qw( getcwd );
use File::Spec;
use File::Temp qw( tempdir );
use IPC::Open3 qw( open3 );
use IO::Async::Loop::Select;
use IO::Select;
use JSON::XS qw( decode_json );
use Log::Log4perl qw( :easy );
use Test::More;
use Time::HiRes qw( time );

use Sonos::System;

sub find_executable($name) {
    return $name if $name =~ m{/} && -x $name;

    for my $directory ( File::Spec->path() ) {
        my $path = File::Spec->catfile( $directory, $name );
        return $path if -f $path && -x $path;
    }

    return;
}

my $fsonos = find_executable( $ENV{FSONOS_SIM_BIN} // 'fsonos' );
plan skip_all => 'Set FSONOS_SIM_BIN or put fsonos on PATH to run simulator integration tests'
  unless $fsonos;

Log::Log4perl->easy_init($OFF);

my $original_dir = getcwd();
my $cache_dir = tempdir( CLEANUP => 1 );
chdir $cache_dir or die "Cannot enter $cache_dir: $!";

my ( $sim_pid, $sim_stdout, $system );
END {
    undef $system;
    if ($sim_pid) {
        kill 'TERM', $sim_pid;
        waitpid( $sim_pid, 0 );
    }
    chdir $original_dir if defined $original_dir;
}

$sim_pid = open3(
    undef,
    $sim_stdout,
    \*STDERR,
    $fsonos,
    'sim',
    '--json',
    '--seeds-out',
    File::Spec->catfile( $cache_dir, 'seeds.toml' ),
);

my $selector = IO::Select->new($sim_stdout);
my $json = '';
my $ready;
my $deadline = time + 15;
while ( time < $deadline && $selector->can_read( $deadline - time ) ) {
    my $line = <$sim_stdout>;
    last unless defined $line;
    $json .= $line;
    $ready = eval { decode_json($json) };
    last if $ready && $ready->{ready};
}
BAIL_OUT('fsonos sim did not report ready within 15 seconds') unless $ready && $ready->{ready};

my ($sim_player) = grep { $_->{room} eq 'Kitchen' } @{ $ready->{players} };
BAIL_OUT('fsonos sim readiness report did not include Kitchen') unless $sim_player;

my $location = "http://$sim_player->{addr}/xml/device_description.xml";
my $loop = IO::Async::Loop::Select->new;
{
    no warnings 'redefine';
    local *UPnP::ControlPoint::searchByType = sub { return };
    $system = Sonos::System->new( $loop, $location );
}

is( $system->numPlayers(), 1, 'loads the simulator device description as one player' );
my $player = $system->player( $sim_player->{room} );
BAIL_OUT('simulator player was not registered') unless $player;

$deadline = time + 5;
while ( !$player->zoneGroupTopology()->haveZoneInfo() && time < $deadline ) {
    $loop->loop_once(0.1);
}
ok( $player->zoneGroupTopology()->haveZoneInfo(), 'receives initial GENA topology state' );
is( $player->zoneName(), 'Kitchen', 'parses the simulator room name' );
is( $player->renderingControl()->getVolume(), 20, 'receives initial rendering-control state' );

$player->renderingControl()->setVolume(37);
$deadline = time + 5;
while ( $player->renderingControl()->getVolume() != 37 && time < $deadline ) {
    $loop->loop_once(0.1);
}
is( $player->renderingControl()->getVolume(), 37, 'volume change reaches the simulator over SOAP and GENA' );

done_testing();