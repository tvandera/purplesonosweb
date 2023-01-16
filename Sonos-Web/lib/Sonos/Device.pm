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
sub processRenderingControl ( $self, $service, %properties ) {
    my $tree = XMLin(
        decode_entities( $properties{LastChange} ),
        forcearray => ["ZoneGroup"],
        keyattr    => {
            "Volume"   => "channel",
            "Mute"     => "channel",
            "Loudness" => "channel"
        }
    );
    #$self->updateRenderState( $tree->{InstanceID} );
}

# called when 'currenty-playing' has changed
sub processAVTransport ( $player, $service, %properties ) {
    my $tree         = XMLin( decode_entities( $properties{LastChange} ) );
    my %instancedata = %{ $tree->{InstanceID} };

    # decode entities
    foreach my $key ( keys %instancedata ) {
        my $val = $instancedata{$key};
        $val                = decode_entities($val) if ( $val =~ /^&lt;/ );
        $val                = \%{ XMLin($val) }     if ( $val =~ /^</ );
        $instancedata{$key} = $val;
    }

    INFO Dumper(\%instancedata);

    #$self->updateAVTransport( \%instancedata );
}

# called when anything in ContentDirectory has been updated
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
###############################################################################
sub upnp_avtransport_repeat {
    my ( $player, $repeat ) = @_;

    my $str = $main::ZONES{$player}->{AV}->{CurrentPlayMode};

    if ( !defined $repeat ) {
        return 0 if ( $str eq "NORMAL" || $str eq "SHUFFLE" );
        return 1;
    }

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;

    if ( $str eq "NORMAL" ) {
        $str = "REPEAT_ALL" if ($repeat);
    }
    elsif ( $str eq "REPEAT_ALL" ) {
        $str = "NORMAL" if ( !$repeat );
    }
    elsif ( $str eq "SHUFFLE_NOREPEAT" ) {
        $str = "SHUFFLE" if ($repeat);
    }
    elsif ( $str eq "SHUFFLE" ) {
        $str = "SHUFFLE_NOREPEAT" if ( !$repeat );
    }
    my $result = $avTransportProxy->SetPlayMode( "0", $str );
    $main::ZONES{$player}->{AV}->{CurrentPlayMode} = $str
      if ( $result->isSuccessful );
    return $repeat;
}
###############################################################################
sub upnp_avtransport_shuffle {
    my ( $player, $shuffle ) = @_;

    my $str = $main::ZONES{$player}->{AV}->{CurrentPlayMode};

    if ( !defined $shuffle ) {
        return 0 if ( $str eq "NORMAL" || $str eq "REPEAT_ALL" );
        return 1;
    }

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;

    if ( $str eq "NORMAL" ) {
        $str = "SHUFFLE_NOREPEAT" if ($shuffle);
    }
    elsif ( $str eq "REPEAT_ALL" ) {
        $str = "SHUFFLE" if ($shuffle);
    }
    elsif ( $str eq "SHUFFLE_NOREPEAT" ) {
        $str = "NORMAL" if ( !$shuffle );
    }
    elsif ( $str eq "SHUFFLE" ) {
        $str = "REPEAT_ALL" if ( !$shuffle );
    }

    my $result = $avTransportProxy->SetPlayMode( "0", $str );
    $main::ZONES{$player}->{AV}->{CurrentPlayMode} = $str
      if ( $result->isSuccessful );
    return $shuffle;
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


