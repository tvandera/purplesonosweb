package Sonos::Discovery;

use v5.36;
use strict;
use warnings;

require UPnP::ControlPoint;
require Sonos::Player;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
$Data::Dumper::Maxdepth = 4;

use constant SERVICE_TYPE => "urn:schemas-upnp-org:device:ZonePlayer:1";

sub new {
    my($self, %args) = @_;
	my $class = ref($self) || $self;

    my $cp = UPnP::ControlPoint->new(%args);
    $self = bless {
        _controlpoint => $cp,
        _players => {}, # UDN => UPnP::ControlPoint
        _zonegroups => {}, # Sonos::ZoneGroup
    }, $class;

    $cp->searchByType( SERVICE_TYPE, sub { $self->_discoveryCallback(@_) });

    return $self;
}

sub numPlayers($self) {
    return scalar keys %{$self->{_players}};
}

sub controlPoint($self) {
    return $self->{_controlpoint};
}

sub sockets($self) {
    return $self->controlPoint()->sockets()
}

# callback routine that gets called by UPnP::Controlpoint when a device is added
# or removed
sub _discoveryCallback {
    my ( $self, $search, $device, $action ) = @_;
    my $location = $device->{LOCATION};

    if ( $action eq 'deviceAdded' ) {
        $self->{_players}->{$location} = Sonos::Player->new($device);
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