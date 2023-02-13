package Sonos::Discovery;

use v5.36;
use strict;
use warnings;

use List::Util qw(all max);

require UPnP::ControlPoint;
require Sonos::Player;
require Sonos::MusicLibrary;

require IO::Async::Handle;
require IO::Async::Loop::Select;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Carp;
use Data::Dumper;
$Data::Dumper::Maxdepth = 4;

use constant SERVICE_TYPE => "urn:schemas-upnp-org:device:ZonePlayer:1";

sub new {
    my($self, $loop) = @_;
	my $class = ref($self) || $self;

    my $cp = UPnP::ControlPoint->new();
    $self = bless {
        _controlpoint => $cp,
        _players => {}, # UDN => Sonos::Player
        _musiclibrary => undef, # Sonos::MusicLibrary
        _loop => undef, # IO::Async::Loop::Select -> added by addToLoop
    }, $class;

    $self->{_musiclibrary} = Sonos::MusicLibrary->new($self);

    $cp->searchByType( SERVICE_TYPE, sub { $self->_discoveryCallback(@_) });

    $self->addToLoop($loop) if defined $loop;

    return $self;
}

sub numPlayers($self) {
    return scalar keys %{$self->{_players}};
}

sub players($self) {
    return values %{$self->{_players}};
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

sub player($self, $uuid) {
   return $self->{_players}->{$uuid};
}

sub zonePlayer($self, $zoneName) {
    my ($player) = grep { $_->zoneName() eq $zoneName } $self->players();
    return $player;
}

sub controlPoint($self) {
    return $self->{_controlpoint};
}

sub musicLibrary($self) {
    return $self->{_musiclibrary};
}

sub sockets($self) {
    return $self->controlPoint()->sockets()
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

# callback routine that gets called by UPnP::Controlpoint when a device is added
# or removed
sub _discoveryCallback {
    my ( $self, $search, $device, $action ) = @_;
    my $uuid = $device->{UDN};

    if ( $action eq 'deviceAdded' ) {
        return if defined $self->{_players}->{$uuid};
        $self->{_players}->{$uuid} = Sonos::Player->new($device, $self);
        INFO "Added device: $device->{FRIENDLYNAME} ($device->{LOCATION})";
        # DEBUG Dumper($device);
    }
    elsif ( $action eq 'deviceRemoved' ) {
        INFO "Removed device: $device->{FRIENDLYNAME} ($device->{LOCATION})";
        delete $self->{_players}->{$uuid};
    }
    else {
        WARNING( "Unknown action name:" . $action );
    }
}