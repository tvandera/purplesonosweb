package Sonos::UPnP;

require UPnP::ControlPoint;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( $DEBUG );

use Data::Dumper;


use constant SERVICE_TYPE =>  "urn:schemas-upnp-org:device:ZonePlayer:1";
use constant SERVICE_NAMES => (
    "ZoneGroupTopology", # zones
    "ContentDirectory",  # music library
    "AVTransport",       # currently playing track
    "RenderingControl"   # volume etc
);

sub new {
        my ($class, $searchaddr) = @_;
        my $cp;

        if ($searchaddr) {
            $cp = UPnP::ControlPoint->new (SearchAddr => $searchaddr);
        } else {
            $cp = UPnP::ControlPoint->new ();
        }

        my $search = $cp->searchByType(SERVICE_TYPE, \&upnp_search_cb);
        $cp->handle();

        return bless {
                _controlpoint => $cp,
                _searchobject  => $search,
        }, $class;
}

END {
    foreach my $sub (keys %main::SUBSCRIPTIONS) {
        Log (2, "Unsubscribe $sub");
        $main::SUBSCRIPTIONS{$sub}->unsubscribe;
    }
}

sub processZoneGroupState($zone, $properties) {
    my $tree = XMLin(decode_entities($properties{"ZoneGroupState"}), forcearray => ["ZoneGroup", "ZoneGroupMember"]);
    my @groups = @{$tree->{ZoneGroups}->{ZoneGroup}};
    foreach my $group (@groups) {
        my %zonegroup = %{$group};
        my $coordinator = $zonegroup{Coordinator};

        foreach my $member (@members) {
            $member->{Coordindator} = $coordinator;
            Sonos::State::addZone($member);
        }
    }
}

sub processThirdPartyMediaServers($zone, $properties) {
    my %mapping = (
        "SA_RINCON1_" => "Rhapsody",
        "SA_RINCON4_" => "Pandora",
        "SA_RINCON6_" => "Sirius"
    );

    my $tree = XMLin(decode_entities($properties{"ThirdPartyMediaServers"}), forcearray => ["Service"]);
    for my $item ( @{ $tree->{Service} } ) {
        while (my ($rincon, $service) = each(%mapping))
        {
            $Sonos::State::addService{$service, $item} if ($item->{UDN} =~ $rincon);
        }
    }
}

sub processRenderingControl($zone, $properties) {
    my $tree = XMLin(decode_entities($properties{LastChange}),
            forcearray => ["ZoneGroup"],
            keyattr=>{"Volume"   => "channel",
                        "Mute"     => "channel",
                        "Loudness" => "channel"});
    $zone->updateRenderState($tree->{InstanceID});
}

sub processAVTransport($zone, $properties) {
    my $tree = XMLin(decode_entities($properties{LastChange}));
    my %instancedata %{$tree->{InstanceID}};

    # decode entities
    foreach my $key (keys %instancedata) {
        my $val = $instancedata[$key];
        $val = decode_entities($val) if ($val =~ /^&lt;/);
        $val = \%{XMLin($val)} if ($val =~ /^</);
        $instancedata[$key] = $val;
    }

    $zone->updateAVTransport(\%instancedata);
}


###############################################################################
# This routine get calles when an update from the Sonos system was received.
# -
sub sonos_upnp_update {
    my ($service, %properties) = @_;
    my $zone = sonos_location_to_id($service->{BASE});

    my %handlers = (
        # serviceId, property key
        ("serviceId:ZoneGroupTopology", "ZoneGroupState") => \&processZoneGroupState,
        ("serviceId:ZoneGroupTopology", "ThirdPartyMediaServers") => \&processThirdPartyMediaServers,

        ("serviceId:RenderingControl",  "LastChange") => \&processRenderingControl,
        ("serviceId:AVTransport",       "LastChange") => \&processAVTransport,

        ("serviceId:ContentDirectory",  "ContainerUpdateIDs") => \&processContainerUpdate,
        ("serviceId:ContentDirectory",  "ShareIndexInProgress") => \&processContainerUpdate,
        ("serviceId:ContentDirectory",  "MasterRadioUpdateID") => \&processContainerUpdate,
        ("serviceId:ContentDirectory",  "SavedQueuesUpdateID") => \&processContainerUpdate,
        ("serviceId:ContentDirectory",  "ShareListUpdateID") => \&processContainerUpdate,
    );

    while (my ($id, $keyProperty, $handler) = each(%handlers)) {
        if (($service->serviceId =~ /serviceId:$id/) and (defined $properties{$keyProperty})) {
            &handler(\%properties);
        }
    }


    if ($service->serviceId =~ /serviceId:ContentDirectory/) {

        if (defined $properties{ContainerUpdateIDs} && $properties{ContainerUpdateIDs} =~ /AI:/) {
            sonos_containers_del("AI:");
        }

        if (!defined $main::ZONES{$zone}->{QUEUE} || $properties{ContainerUpdateIDs} =~ /Q:0/) {
            Log (2, "Refetching Q for $main::ZONES{$zone}->{ZoneName} updateid $properties{ContainerUpdateIDs}");
            $main::ZONES{$zone}->{QUEUE} = upnp_content_dir_browse($zone, "Q:0");
            $main::LASTUPDATE = $main::SONOS_UPDATENUM;
            $main::QUEUEUPDATE{$zone} = $main::SONOS_UPDATENUM++;
            sonos_process_waiting("QUEUE", $zone);
        }

        if (defined $properties{ShareIndexInProgress}) {
            $main::UPDATEID{ShareIndexInProgress} = $properties{ShareIndexInProgress};
        }

        if (defined $properties{MasterRadioUpdateID} && ($properties{MasterRadioUpdateID} ne $main::UPDATEID{MasterRadioUpdateID})) {
            $main::UPDATEID{MasterRadioUpdateID} = $properties{MasterRadioUpdateID};
            sonos_containers_del("R:0/0");
        }

        if (defined $properties{SavedQueuesUpdateID} && $properties{SavedQueuesUpdateID} ne $main::UPDATEID{SavedQueuesUpdateID}) {
            $main::UPDATEID{SavedQueuesUpdateID} = $properties{SavedQueuesUpdateID};
            sonos_containers_del("SQ:");
        }

        if (defined $properties{ShareListUpdateID} && $properties{ShareListUpdateID} ne $main::UPDATEID{ShareListUpdateID}) {
            $main::UPDATEID{ShareListUpdateID} = $properties{ShareListUpdateID};
            Log (2, "Refetching Index, update id $properties{ShareListUpdateID}");
        }
        return;
    }
}


###############################################################################
sub sonos_renew_subscriptions {
    foreach my $sub (keys %main::SUBSCRIPTIONS) {
        Log (3, "renew $sub");
        my $previousStart = $main::SUBSCRIPTIONS{$sub}->{_startTime};
        $main::SUBSCRIPTIONS{$sub}->renew();
        if($previousStart == $main::SUBSCRIPTIONS{$sub}->{_startTime}) {
            Log (1, "renew failed " . Dumper($@));
            # Renew failed, lets subscribe again
            my ($location, $name) = split (",", $sub);
            my $device = $main::DEVICE{$location};
            my $service = upnp_device_get_service($device, $name);
            $main::SUBSCRIPTIONS{$location . "-" . $name} = $service->subscribe(\&sonos_upnp_update);
        }
    }
    add_timeout(time()+$main::RENEW_SUB_TIME, \&sonos_renew_subscriptions);
}

sub upnp_device_get_service {
    my ($device, $name) = @_;
    Log(2, "Service for $name/$device");
    return undef unless $name;
    return undef unless $device;
    my $service = $device->getService($name);
    return $service if ($service);

    for my $child ($device->children) {
        $service = $child->getService($name);
        return $service if ($service);
    }
    main::Log(0, "Device '$device' with name '$name' not found");
    return undef;
}

###############################################################################
sub upnp_zone_get_service {
    my ($zone, $name) = @_;

    if (! exists $main::ZONES{$zone} ||
        ! defined $main::ZONES{$zone}->{Location} ||
        ! defined $main::DEVICE{$main::ZONES{$zone}->{Location}}) {
        main::Log(0, "Zone '$zone' not found");
        return undef;
    }

    return upnp_device_get_service($main::DEVICE{$main::ZONES{$zone}->{Location}}, $name);
}


###############################################################################
sub sonos_add_radio {
    my ($name, $station) = @_;
    Log(3, "Adding radio name:$name, station:$station");

    $station = substr($station, 5) if (substr($station, 0, 5) eq "http:");
    $name = enc($name);

    my $item = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" ' .
               'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" ' .
               'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">' .
               '<item id="" restricted="false"><dc:title>' .
               $name . '</dc:title><res>x-rincon-mp3radio:' .
               $station .  '</res></item></DIDL-Lite>';

    my ($zone) = split(",", $main::UPDATEID{MasterRadioUpdateID});
    return upnp_content_dir_create_object($zone, "R:0/0", $item);
}

###############################################################################
sub upnp_content_dir_create_object {
    my ($zone, $containerid, $elements) = @_;
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    return undef if (! defined $contentDir);
    my $contentDirProxy = $contentDir->controlProxy;
    my $result = $contentDirProxy->CreateObject($containerid, $elements);
    return $result;
}
###############################################################################
sub upnp_content_dir_destroy_object {
    my ($zone, $objectid) = @_;
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    return undef if (! defined $contentDir);
    my $contentDirProxy = $contentDir->controlProxy;
    my $result = $contentDirProxy->DestroyObject($objectid);
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
    my ($zone, $objectid, $type) = @_;

    $type = 'BrowseDirectChildren' if (!defined $type);

    Log(4, "zone: $zone objectid: $objectid type: $type");

    my $start = 0;
    my @data = ();
    my $result;

    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    return undef if (! defined $contentDir);
    my $contentDirProxy = $contentDir->controlProxy;

    do {
        $result = $contentDirProxy->Browse($objectid, $type,
                                           'dc:title,res,dc:creator,upnp:artist,upnp:album',
                                           $start, 2000, "");

        return undef if (!$result->isSuccessful);

        $start += $result->getValue("NumberReturned");

        my $results = $result->getValue("Result");
        my $tree = XMLin($results, forcearray => ["item", "container"], keyattr=>{});

        push(@data, @{$tree->{item}}) if (defined $tree->{item});
        push(@data, @{$tree->{container}}) if (defined $tree->{container});
    } while ($start < $result->getValue("TotalMatches"));

    return \@data;
}


# Used to remove
# - a radio station
# - a play list
sub upnp_content_dir_delete {
    my ($zone, $objectid) = @_;

    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    my $contentDirProxy = $contentDir->controlProxy;

    $contentDirProxy->DestroyObject($objectid);
}

###############################################################################
sub upnp_content_dir_refresh_share_index {
    my ($zone) = split(",", $main::UPDATEID{ShareListUpdateID});
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");

    if (! defined $contentDir) {
        if ($zone eq "") {
            Log(0, "Main zone not found yet, will retry.  Windows XP *WILL* require rerunning SonosWeb after selecting 'Unblock' in the Windows Security Alert.");
        } else {
            Log(1, "$zone not available, will retry");
        }
        add_timeout (time()+5, \&upnp_content_dir_refresh_share_index);
        return
    }
    my $contentDirProxy = $contentDir->controlProxy;
    $contentDirProxy->RefreshShareIndex();
}

###############################################################################
sub upnp_avtransport_remove_track {
    my ($zone, $objectid) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->RemoveTrackFromQueue("0", $objectid);
    return;
}
###############################################################################
sub upnp_avtransport_play {
    my ($zone) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->Play("0", "1");
    return $result;
}
###############################################################################
sub upnp_avtransport_seek {
    my ($zone,$queue) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    $queue =~ s,^.*/,,;

    my $result = $avTransportProxy->Seek("0", "TRACK_NR", $queue);
    return $result;
}
###############################################################################
sub upnp_render_mute {
    my ($zone,$on) = @_;

    if (!defined $on) {
        return $main::ZONES{$zone}->{RENDER}->{Mute}->{Master}->{val};
    }

    my $render = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:RenderingControl:1");
    my $renderProxy = $render->controlProxy;
    my $result = $renderProxy->SetMute("0", "Master", $on);
    $main::ZONES{$zone}->{RENDER}->{Mute}->{Master}->{val} = $on if ($result->isSuccessful);
    return $on;
}
###############################################################################
sub upnp_render_volume_change {
    my ($volzone,$change) = @_;

    foreach my $zone (keys %main::ZONES) {
        if ($volzone eq $main::ZONES{$zone}->{Coordinator}) {
            my $vol = $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val} + $change;
            upnp_render_volume($zone,$vol);
        }
    }
}
###############################################################################
sub upnp_render_volume {
    my ($zone,$vol) = @_;

    if (!defined $vol) {
        return $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val};
    }

    $vol = 100 if ($vol > 100);
    $vol = 0 if ($vol < 0);

    my $render = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:RenderingControl:1");
    my $renderProxy = $render->controlProxy;
    my $result = $renderProxy->SetVolume("0", "Master", $vol);
    if ($result->isSuccessful) {
        $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val} = $vol if ($result->isSuccessful);
    } else {
        Log (2, "SetVolume error:\n", Dumper($result));
    }
    return $vol;
}
###############################################################################
sub upnp_avtransport_action {
    my ($zone,$action) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->$action("0");
    return $result;
}
###############################################################################
sub upnp_avtransport_repeat {
    my ($zone, $repeat) = @_;

    my $str = $main::ZONES{$zone}->{AV}->{CurrentPlayMode};

    if (!defined $repeat) {
        return 0 if ($str eq "NORMAL" || $str eq "SHUFFLE");
        return 1;
    }

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    if ($str eq "NORMAL") {
        $str = "REPEAT_ALL" if ($repeat);
    } elsif ($str eq "REPEAT_ALL") {
        $str = "NORMAL" if (!$repeat);
    } elsif ($str eq "SHUFFLE_NOREPEAT") {
        $str = "SHUFFLE" if ($repeat);
    } elsif ($str eq "SHUFFLE") {
        $str = "SHUFFLE_NOREPEAT" if (!$repeat);
    }
    my $result = $avTransportProxy->SetPlayMode("0", $str);
    $main::ZONES{$zone}->{AV}->{CurrentPlayMode} = $str if ($result->isSuccessful);
    return $repeat;
}
###############################################################################
sub upnp_avtransport_shuffle {
    my ($zone, $shuffle) = @_;

    my $str = $main::ZONES{$zone}->{AV}->{CurrentPlayMode};

    if (!defined $shuffle) {
        return 0 if ($str eq "NORMAL" || $str eq "REPEAT_ALL");
        return 1;
    }

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    if ($str eq "NORMAL") {
        $str = "SHUFFLE_NOREPEAT" if ($shuffle);
    } elsif ($str eq "REPEAT_ALL") {
        $str = "SHUFFLE" if ($shuffle);
    } elsif ($str eq "SHUFFLE_NOREPEAT") {
        $str = "NORMAL" if (!$shuffle);
    } elsif ($str eq "SHUFFLE") {
        $str = "REPEAT_ALL" if (!$shuffle);
    }

    my $result = $avTransportProxy->SetPlayMode("0", $str);
    $main::ZONES{$zone}->{AV}->{CurrentPlayMode} = $str if ($result->isSuccessful);
    return $shuffle;
}
###############################################################################
sub upnp_avtransport_set_uri {
    my ($zone, $uri, $metadata) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;
    my $result = $avTransportProxy->SetAVTransportURI(0, $uri, $metadata);
    return $result;
}

###############################################################################
sub upnp_avtransport_add_uri {
    my ($zone, $uri, $metadata, $queueSlot) = @_;

    Log (2, "zone=$zone uri=$uri metadata=$metadata");

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->AddURIToQueue(0, $uri, $metadata, $queueSlot);
    return $result;
}

###############################################################################
sub upnp_avtransport_standalone_coordinator {
    my ($zone) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;
    my $result = $avTransportProxy->BecomeCoordinatorOfStandaloneGroup(0);
    return $result;
}

###############################################################################
sub upnp_avtransport_save {
    my ($zone, $name) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;
    my $result = $avTransportProxy->SaveQueue(0, $name, "");
    return $result;
}
###############################################################################

# callback routine that gets called by UPnP::Controlpoint when a device is added
# or removed
sub upnp_search_cb {
    my ($search, $device, $action) = @_;
    if ($action eq 'deviceAdded') {
       INFO("Added name: " . $device->friendlyName . "\n" .
               "Location: " .  $device->{LOCATION} . "\n" .
               "UDN: " .  $device->{UDN} . "\n" .
               "type: " . $device->deviceType()
               );
       DEBUG(Dumper($device));


#       next if ($device->{LOCATION} !~ /xml\/zone_player.xml/);
        $main::DEVICE{$device->{LOCATION}} = $device;

#                             urn:schemas-upnp-org:service:DeviceProperties:1

        foreach my $name (qw(urn:schemas-upnp-org:service:ZoneGroupTopology:1
                             urn:schemas-upnp-org:service:ContentDirectory:1
                             urn:schemas-upnp-org:service:AVTransport:1
                             urn:schemas-upnp-org:service:RenderingControl:1)) {
            my $service = upnp_device_get_service($device, $name);
            $main::SUBSCRIPTIONS{$device->{LOCATION} . "-" . $name} = $service->subscribe(\&sonos_upnp_update);
        }
    }
    elsif ($action eq 'deviceRemoved') {
        INFO("Removed name:" . $device->friendlyName . " zone=" . substr($device->{UDN}, 5));
        delete $main::ZONES{substr($device->{UDN}, 5)};
    } else {
        WARNING("Unknown action name:" . $device->friendlyName);
    }
}
