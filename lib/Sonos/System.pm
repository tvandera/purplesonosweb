package Sonos::System;

use v5.36;
use strict;
use warnings;

use List::Util qw(all max);

require UPnP::ControlPoint;

require Sonos;
require Sonos::Player;
require Sonos::MusicLibrary;
require Sonos::AlbumArtCache;

require IO::Async::Handle;
require IO::Async::Loop::Select;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init(
    $DEBUG
);

use Carp;
use Data::Dumper;
$Data::Dumper::Maxdepth = 4;

use constant SERVICE_TYPE => "urn:schemas-upnp-org:device:ZonePlayer:1";

sub discover {
    my $self = shift;
    return $self->new(@_);
}


sub new {
    my($self, $loop, @locations) = @_;
	my $class = ref($self) || $self;

    my $cp = UPnP::ControlPoint->new();
    $self = bless {
        _controlpoint => $cp,
        _players => {}, # UDN => Sonos::Player
        _musiclibrary => undef, # Sonos::MusicLibrary
        _aacache => undef, # Sonos::AlbumArtCache
        _loop => undef, # IO::Async::Loop::Select -> added by addToLoop
        _callbacks => [ ],
    }, $class;

    $self->{_musiclibrary} = Sonos::MusicLibrary->new($self);
    $self->{_aacache} = Sonos::AlbumArtCache->new($self);

    $self->addToLoop($loop) if defined $loop;

    INFO "Sonos v" . $self->version() . " starting\n";

    for (@locations) {
        my $device = $cp->addByLocation($_);
        $self->addPlayer($device) if $device;
    }

    $cp->searchByType( SERVICE_TYPE, sub { $self->_discoveryCallback(@_) });


    return $self;
}

sub numPlayers($self) {
    return scalar keys %{$self->{_players}};
}

sub version($self) {
    return $Sonos::VERSION;
}

sub TO_JSON($self, $qf) {
    my $player_info = {};
    my $player = 0;
    if ($qf->{"zone"}) {
        $player = $self->player($qf->{"zone"});
        $player_info = $player->TO_JSON(1);
    }

    return {
       "version"     => $self->version(),
       "last_update" => $self->lastUpdate(),
       "players"     => [ map { $_->TO_JSON($player == $_) } $self->players() ],
       "player"      => $player_info,
       "music"       => $self->musicLibrary()->TO_JSON($qf),
    }
}

sub players($self) {
    my @players = values %{$self->{_players}};
    @players = sort { $a->cmp($b) } @players;
    return @players;
}

sub linkAllZones($self, $coordinator) {
    # take first as coordinator if no coordinator given
    my @players = $self->players();
    $coordinator = shift @players unless $coordinator;
    return $coordinator->zoneGroupTopology()->linkAllZones();
}

sub lastUpdate($self) {
    my @values = map { $_->lastUpdate() } $self->players();
    return max @values;
}

sub populated($self) {
    return
        ( $self->numPlayers() > 0 and
         all { $_->populated() } $self->players() );
}

sub wait($self) {
    while (!$self->populated()) {
        $self->loop()->loop_once();
    }

    return $self;
}

sub player($self, $name_or_uuid) {
   carp "Need \$name_or_uuid" unless $name_or_uuid;
   my $player = $self->{_players}->{$name_or_uuid};
   return $player if $player;
   ($player) = grep { $_->zoneName() eq $name_or_uuid } $self->players();
    return $player;
}

sub controlPoint($self) {
    return $self->{_controlpoint};
}

sub musicLibrary($self) {
    return $self->{_musiclibrary};
}

sub albumArtCache($self) {
    return $self->{_aacache};
}

sub sockets($self) {
    return $self->controlPoint()->sockets()
}

sub loop($self) {
    return $self->{_loop};
}

sub log($self, $comp, @args) {
    INFO sprintf("[%12s]: ", $comp), @args;
}

sub addToLoop($self, $loop) {
    carp "No a IO::Async::Loop::Select" unless $loop isa 'IO::Async::Loop::Select';
    carp "Already added" if defined $self->{_loop};

    $self->{_loop} = $loop;

    for my $socket ($self->sockets()) {
        my $handle = IO::Async::Handle->new(
            handle => $socket,
            on_read_ready => sub {
                $self->controlPoint()->handleOnce($socket);
            },
            on_write_ready => sub { carp },
        );

        $loop->add( $handle );
    }
}

sub addPlayer($self, $device) {
    my $uuid = $device->{UDN};
    $uuid =~ s/^uuid://g;

    return if defined $self->{_players}->{$uuid};
    $self->{_players}->{$uuid} = Sonos::Player->new($device, $self);
    INFO "Added device: $device->{FRIENDLYNAME} ($device->{LOCATION})";
}

sub removePlayer($self, $device) {
    my $uuid = $device->{UDN};
    $uuid =~ s/^uuid://g;

    INFO "Removed device: $device->{FRIENDLYNAME} ($device->{LOCATION})";
    delete $self->{_players}->{$uuid};
}

# callback routine that gets called by UPnP::Controlpoint when a device is added
# or removed
sub _discoveryCallback {
    my ( $self, $search, $device, $action ) = @_;

    if ( $action eq 'deviceAdded' ) {
        $self->addPlayer($device);
    }
    elsif ( $action eq 'deviceRemoved' ) {
        $self->removePlayer($device);
    }
    else {
        WARNING( "Unknown action name:" . $action );
    }
}

sub onUpdate($self, $callback) {
    push @{$self->{_callbacks}}, $callback;
}

sub doCallBacks($self) {
    $_->($self) for @{$self->{_callbacks}};
    $self->{_callbacks} = [];
}