package Sonos::Device;

use v5.36;
use strict;
use warnings;

require UPnP::ControlPoint;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

use HTML::Entities;

use Data::Dumper;
use Carp;

use constant SERVICE_TYPE => "urn:schemas-upnp-org:device:ZonePlayer:1";

use constant SERVICE_PREFIX => "urn:schemas-upnp-org:service:";
use constant SERVICE_SUFFIX => ":1";

use constant SERVICE_NAMES => (
    "ZoneGroupTopology",    # zones
    "ContentDirectory",     # music library
    "AVTransport",          # currently playing track
    "RenderingControl"      # volume etc
);

package Sonos::Device;

sub new {
    my($self, $upnp, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _upnp => $upnp,
        _subscriptions => {},
        _contentdirectory => undef, #  Sonos::ContentDirectory
        _avtransport => {},
    }, $class;

    $self->{_contentdirectory} = Sonos::ContentDirectory->new($self);
    $self->renewSubscriptions();

    return $self;
}

sub DESTROY($self)
{
    map { $_->unsubscribe if defined } values(%{$self->{_subscriptions}});
}

sub getSubscription($self, $name) {
    return $self->{_subscriptions}->{$name};
}

sub getService($self, $name) {
    $name = SERVICE_PREFIX . $name . SERVICE_SUFFIX;
    my $device = $self->{_upnp};

    my $service = $device->getService($name);
    return $service if $service;

   for my $child ( $device->children ) {
        $service = $child->getService($name);
        return $service if ($service);
    }

}

# called when zonegroups have changed
sub processZoneGroupTopology ( $self, $service, %properties ) {
    my $tree = XMLin(
        decode_entities( $properties{"ZoneGroupState"} ),
        forcearray => [ "ZoneGroup", "ZoneGroupMember" ]
    );

    my @groups = @{ $tree->{ZoneGroups}->{ZoneGroup} };
    DEBUG "Found " . scalar(@groups) . " zone groups: ";
    foreach my $group (@groups) {
        my %zonegroup   = %{$group};
        my $coordinator = $zonegroup{Coordinator};
        my @members     = @{ $zonegroup{ZoneGroupMember} };

        foreach my $member (@members) {
            $member->{Coordindator} = $coordinator;
        }
    }


}

# not currently called, should be called from processZoneGroupTopology
sub processThirdPartyMediaServers ( $self, $properties ) {
    my %mapping = (
        "SA_RINCON1_" => "Rhapsody",
        "SA_RINCON4_" => "Pandora",
        "SA_RINCON6_" => "Sirius"
    );

    my $tree =
      XMLin( decode_entities( $properties->{"ThirdPartyMediaServers"} ),
        forcearray => ["Service"] );
    for my $item ( @{ $tree->{Service} } ) {
        while ( my ( $rincon, $service ) = each(%mapping) ) {
            Sonos::State::addService( $service, $item )
              if ( $item->{UDN} =~ $rincon );
        }
    }
}

# called when rendering properties (like volume) are changed
# called when 'currently-playing' has changed
sub processRenderingControlAndAVTransport ( $self, $service, %properties ) {
    my $tree = XMLin(
        decode_entities( $properties{LastChange} ),
        forcearray => ["ZoneGroup"],
        keyattr    => {
            "Volume"   => "channel",
            "Mute"     => "channel",
            "Loudness" => "channel"
        }
    );
    my %instancedata = %{ $tree->{InstanceID} };

    # many of these propoerties are XML html-encodeded
    # entities. Decode + parse XML + extract "val" attr
    foreach my $key ( keys %instancedata ) {
        my $val = $instancedata{$key};
        $val = decode_entities($val) if ( $val =~ /^&lt;/ );
        $val = \%{ XMLin($val) }     if ( $val =~ /^</ );
        $val = $val->{val} if ref($val) eq 'HASH';
        $instancedata{$key} = $val
    }

    $self->{_state} = \%instancedata;
}


# called when anything in ContentDirectory has been updated
# forward to _contentdirectory member
sub processContentDirectory ( $self, $service, %properties ) {
    $self->{_contentdirectory}->processUpdate($service, %properties);
}

###############################################################################
sub renewSubscriptions($self) {
    for my $name (SERVICE_NAMES) {
        my $sub = $self->getSubscription($name);
        if (defined $sub) {
            $sub->renew();
        } else {
            my $service = $self->getService($name) or
                carp("Could not find service: $name");
            my $updatemethod = "process" . $name;
            $self->{_subscriptions}->{$name} = $service->subscribe( sub { $self->$updatemethod(@_); }  ) or
                carp("Could not subscribe to \"$name\"");
        }
    }

    # add_timeout( time() + $main::RENEW_SUB_TIME, \&sonos_renew_subscriptions );
}

sub avTransportProxy($self) {
    return $self->getService("AVTransport")->controlProxy;
}

sub renderProxy($self) {
    return $self->getService("RenderingControl")->controlProxy;
}

sub removeTrackFromQueue($self, $objectid) {
    return $self->avTransportProxy()->RemoveTrackFromQueue( "0", $objectid );
}

sub startPlaying($self) {
    return $self->avTransportProxy()->Play( "0", "1" );
}

sub seek($self, $queue) {
    $queue =~ s,^.*/,,;
    return $self->avTransportProxy()->Seek( "0", "TRACK_NR", $queue );
}

###############################################################################

sub upnp_render_mute {
    my ( $player, $on ) = @_;

    if ( !defined $on ) {
        return $main::ZONES{$player}->{RENDER}->{Mute}->{Master}->{val};
    }

    my $render = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:RenderingControl:1" );
    my $renderProxy = $render->controlProxy;
    my $result      = $renderProxy->SetMute( "0", "Master", $on );
    $main::ZONES{$player}->{RENDER}->{Mute}->{Master}->{val} = $on
      if ( $result->isSuccessful );
    return $on;
}
###############################################################################
sub upnp_render_volume_change {
    my ( $volzone, $change ) = @_;

    foreach my $player ( keys %main::ZONES ) {
        if ( $volzone eq $main::ZONES{$player}->{Coordinator} ) {
            my $vol =
              $main::ZONES{$player}->{RENDER}->{Volume}->{Master}->{val} +
              $change;
            upnp_render_volume( $player, $vol );
        }
    }
}
###############################################################################
sub upnp_render_volume {
    my ( $player, $vol ) = @_;

    if ( !defined $vol ) {
        return $main::ZONES{$player}->{RENDER}->{Volume}->{Master}->{val};
    }

    $vol = 100 if ( $vol > 100 );
    $vol = 0   if ( $vol < 0 );

    my $render = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:RenderingControl:1" );
    my $renderProxy = $render->controlProxy;
    my $result      = $renderProxy->SetVolume( "0", "Master", $vol );
    if ( $result->isSuccessful ) {
        $main::ZONES{$player}->{RENDER}->{Volume}->{Master}->{val} = $vol
          if ( $result->isSuccessful );
    }
    else {
        Log( 2, "SetVolume error:\n", Dumper($result) );
    }
    return $vol;
}
###############################################################################
sub upnp_avtransport_action {
    my ( $player, $action ) = @_;

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->$action("0");
    return $result;
}

sub getRepeat($self) {
    return $self->{_state}->{CurrentPlayMode} =~ /^REPEAT/;
}

sub getShuffle($self) {
    return $self->{_state}->{CurrentPlayMode} =~ /^SHUFFLE/;
}

sub switchPlayMode($self, %switch_map) {
    push %switch_map, reverse %switch_map;
    my $new_playmode = $switch_map{$self->GetPlayMode()};
    $self->action("SetPlayMode", $new_playmode)
}

# if called with $on_or_off, sets repeat mode to this value
# if called with $on_of_off == undef, switches repeat mode
sub setRepeat($self, $on_or_off) {
    # nothing to do
    return if $self->getRepeat() == $on_or_off;

    my %switch_repeat = (
        "NORMAL"  => "REPEAT_ALL",
        "SHUFFLE" => "SHUFFLE_NOREPEAT",
    );
    $self->switchPlayMode(%switch_repeat);
}


# if called with $on_or_off, sets shuffle mode to this value
# if called with $on_of_off == undef, switches shuffle mode
sub setShuffle($self, $on_or_off) {
    # nothing to do
    return if $self->getShuffle() == $on_or_off;

    my %switch_shuffle = (
        "NORMAL"     => "SHUFFLE_NOREPEAT",
        "REPEAT_ALL" => "SHUFFLE",
    );
    $self->switchPlayMode(%switch_shuffle);
}

###############################################################################
sub upnp_avtransport_set_uri {
    my ( $player, $uri, $metadata ) = @_;

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;
    my $result = $avTransportProxy->SetAVTransportURI( 0, $uri, $metadata );
    return $result;
}

###############################################################################
sub upnp_avtransport_add_uri {
    my ( $player, $uri, $metadata, $queueSlot ) = @_;

    Log( 2, "player=$player uri=$uri metadata=$metadata" );

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;

    my $result =
      $avTransportProxy->AddURIToQueue( 0, $uri, $metadata, $queueSlot );
    return $result;
}

###############################################################################
sub upnp_avtransport_standalone_coordinator {
    my ($player) = @_;

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;
    my $result = $avTransportProxy->BecomeCoordinatorOfStandaloneGroup(0);
    return $result;
}


