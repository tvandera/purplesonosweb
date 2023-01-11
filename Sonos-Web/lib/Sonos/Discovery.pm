package Sonos::Discovery;

use v5.36;
use strict;
use warnings;

require UPnP::ControlPoint;
require Sonos::Device;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;

use constant SERVICE_TYPE => "urn:schemas-upnp-org:device:ZonePlayer:1";

sub new {
    my($self, %args) = @_;
	my $class = ref($self) || $self;

    my $cp = UPnP::ControlPoint->new(%args);
    $self = bless {
        _controlpoint => $cp,
        _devices => {},
    }, $class;

    $cp->searchByType( SERVICE_TYPE, sub { $self->discovery_callback(@_) });
    $cp->handle();

    return $self;
}

# callback routine that gets called by UPnP::Controlpoint when a device is added
# or removed
sub discovery_callback {
    my ( $self, $search, $device, $action ) = @_;
    my $location = $device->{LOCATION};

    if ( $action eq 'deviceAdded' ) {
        $self->{_devices}->{$location} = $device;
    }
    elsif ( $action eq 'deviceRemoved' ) {
        delete $self->{_devices}->{$location};
    }
    else {
        WARNING( "Unknown action name:" . $action );
    }
}