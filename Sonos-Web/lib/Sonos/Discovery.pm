package Sonos::Discovery;

use v5.36;
use strict;
use warnings;

require UPnP::ControlPoint;
require Sonos::Player;
require Sonos::ContentCache;

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
        _contentcache => Sonos::ContentCache->new("global"),
        _loop => undef, # IO::Async::Loop::Select
    }, $class;

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

sub zonePlayer($self, $zoneName) {
    my @matches = grep { $_->zoneName() == $zoneName } $self->players();
    return undef unless scalar @matches;
    carp "More than one player for zone \"$zoneName\"" unless scalar @matches == 1;
    return $matches[0];
}

sub controlPoint($self) {
    return $self->{_controlpoint};
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
    my $location = $device->{LOCATION};

    if ( $action eq 'deviceAdded' ) {
        $self->{_players}->{$location} = Sonos::Player->new($device, $self);
        INFO "Found device: $device->{FRIENDLYNAME} ($device->{LOCATION})";
        # DEBUG Dumper($device);
    }
    elsif ( $action eq 'deviceRemoved' ) {
        delete $self->{_players}->{$location};
    }
    else {
        WARNING( "Unknown action name:" . $action );
    }
}