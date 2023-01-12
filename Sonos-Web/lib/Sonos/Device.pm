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
    }, $class;

    $self->renewSubscriptions();

    return $self;
}

sub DESTROY
{
    my $self = shift;
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


sub processZoneGroupTopology ( $self, $service, %properties ) {
    my $tree = XMLin(
        decode_entities( $properties{"ZoneGroupState"} ),
        forcearray => [ "ZoneGroup", "ZoneGroupMember" ]
    );

    INFO "Found ZoneGroup: ";
    DEBUG Dumper( $tree );
    my @groups = @{ $tree->{ZoneGroups}->{ZoneGroup} };
    foreach my $group (@groups) {
        my %zonegroup   = %{$group};
        my $coordinator = $zonegroup{Coordinator};
        my @members     = @{ $zonegroup{ZoneGroupMember} };

        foreach my $member (@members) {
            $member->{Coordindator} = $coordinator;
        }
    }
}

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
    $self->updateRenderState( $tree->{InstanceID} );
}

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

    #$player->updateAVTransport( \%instancedata );
}

sub processContentDirectory ( $player, $service, %properties ) {
    INFO Dumper(\%properties);
    if ( defined $properties{ContainerUpdateIDs}
        && $properties{ContainerUpdateIDs} =~ /AI:/ )
    {
        sonos_containers_del("AI:");
    }

    if ( !defined $main::ZONES{$player}->{QUEUE}
        || $properties{ContainerUpdateIDs} =~ /Q:0/ )
    {
        INFO "Refetching Q for $main::ZONES{$player}->{ZoneName} updateid $properties{ContainerUpdateIDs}";
        $main::ZONES{$player}->{QUEUE} =
            upnp_content_dir_browse( $player, "Q:0" );
        $main::LASTUPDATE = $main::SONOS_UPDATENUM;
        $main::QUEUEUPDATE{$player} = $main::SONOS_UPDATENUM++;
        sonos_process_waiting( "QUEUE", $player );
    }

    if ( defined $properties{ShareIndexInProgress} ) {
        $main::UPDATEID{ShareIndexInProgress} =
            $properties{ShareIndexInProgress};
    }

    if (
        defined $properties{MasterRadioUpdateID}
        && ( $properties{MasterRadioUpdateID} ne
            $main::UPDATEID{MasterRadioUpdateID} )
        )
    {
        $main::UPDATEID{MasterRadioUpdateID} =
            $properties{MasterRadioUpdateID};
        sonos_containers_del("R:0/0");
    }

    if ( defined $properties{SavedQueuesUpdateID}
        && $properties{SavedQueuesUpdateID} ne
        $main::UPDATEID{SavedQueuesUpdateID} )
    {
        $main::UPDATEID{SavedQueuesUpdateID} =
            $properties{SavedQueuesUpdateID};
        sonos_containers_del("SQ:");
    }

    if ( defined $properties{ShareListUpdateID}
        && $properties{ShareListUpdateID} ne
        $main::UPDATEID{ShareListUpdateID} )
    {
        $main::UPDATEID{ShareListUpdateID} = $properties{ShareListUpdateID};
        Log( 2,
            "Refetching Index, update id $properties{ShareListUpdateID}" );
    }
    return;
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

###############################################################################
sub sonos_add_radio {
    my ( $name, $station ) = @_;
    Log( 3, "Adding radio name:$name, station:$station" );

    $station = substr( $station, 5 ) if ( substr( $station, 0, 5 ) eq "http:" );
    $name    = enc($name);

    my $item =
        '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" '
      . 'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
      . 'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
      . '<item id="" restricted="false"><dc:title>'
      . $name
      . '</dc:title><res>x-rincon-mp3radio:'
      . $station
      . '</res></item></DIDL-Lite>';

    my ($player) = split( ",", $main::UPDATEID{MasterRadioUpdateID} );
    return upnp_content_dir_create_object( $player, "R:0/0", $item );
}

###############################################################################
sub upnp_content_dir_create_object {
    my ( $player, $containerid, $elements ) = @_;
    my $contentDir = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:ContentDirectory:1" );
    return undef if ( !defined $contentDir );
    my $contentDirProxy = $contentDir->controlProxy;
    my $result = $contentDirProxy->CreateObject( $containerid, $elements );
    return $result;
}
###############################################################################
sub upnp_content_dir_destroy_object {
    my ( $player, $objectid ) = @_;
    my $contentDir = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:ContentDirectory:1" );
    return undef if ( !defined $contentDir );
    my $contentDirProxy = $contentDir->controlProxy;
    my $result          = $contentDirProxy->DestroyObject($objectid);
    return $result;
}
###############################################################################
# objectid is like :
# - AI: for audio-in
# - Q:0 for queue
#
# type is
#  - "BrowseMetadata", or
#  - "BrowseDirectChildren"
sub upnp_content_dir_browse {
    my ( $player, $objectid, $type ) = @_;

    $type = 'BrowseDirectChildren' if ( !defined $type );

    DEBUG "player: $player objectid: $objectid type: $type";

    my $start = 0;
    my @data  = ();
    my $result;

    my $contentDir = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:ContentDirectory:1" );
    return undef if ( !defined $contentDir );
    my $contentDirProxy = $contentDir->controlProxy;

    do {
        $result =
          $contentDirProxy->Browse( $objectid, $type,
            'dc:title,res,dc:creator,upnp:artist,upnp:album',
            $start, 2000, "" );

        return undef if ( !$result->isSuccessful );

        $start += $result->getValue("NumberReturned");

        my $results = $result->getValue("Result");
        my $tree    = XMLin(
            $results,
            forcearray => [ "item", "container" ],
            keyattr    => {}
        );

        push( @data, @{ $tree->{item} } ) if ( defined $tree->{item} );
        push( @data, @{ $tree->{container} } )
          if ( defined $tree->{container} );
    } while ( $start < $result->getValue("TotalMatches") );

    return \@data;
}

# Used to remove
# - a radio station
# - a play list
sub upnp_content_dir_delete {
    my ( $player, $objectid ) = @_;

    my $contentDir = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:ContentDirectory:1" );
    my $contentDirProxy = $contentDir->controlProxy;

    $contentDirProxy->DestroyObject($objectid);
}

###############################################################################
sub upnp_content_dir_refresh_share_index {
    my ($player) = split( ",", $main::UPDATEID{ShareListUpdateID} );
    my $contentDir = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:ContentDirectory:1" );

    if ( !defined $contentDir ) {
        if ( $player eq "" ) {
            WARN
"Main player not found yet, will retry.  Windows XP *WILL* require rerunning SonosWeb after selecting 'Unblock' in the Windows Security Alert.";
        }
        else {
            WARN "$player not available, will retry";
        }
        add_timeout( time() + 5, \&upnp_content_dir_refresh_share_index );
        return;
    }
    my $contentDirProxy = $contentDir->controlProxy;
    $contentDirProxy->RefreshShareIndex();
}

###############################################################################
sub upnp_avtransport_remove_track {
    my ( $player, $objectid ) = @_;

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->RemoveTrackFromQueue( "0", $objectid );
    return;
}
###############################################################################
sub upnp_avtransport_play {
    my ($player) = @_;

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->Play( "0", "1" );
    return $result;
}
###############################################################################
sub upnp_avtransport_seek {
    my ( $player, $queue ) = @_;

    my $avTransport = upnp_zone_get_service( $player,
        "urn:schemas-upnp-org:service:AVTransport:1" );
    my $avTransportProxy = $avTransport->controlProxy;

    $queue =~ s,^.*/,,;

    my $result = $avTransportProxy->Seek( "0", "TRACK_NR", $queue );
    return $result;
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


