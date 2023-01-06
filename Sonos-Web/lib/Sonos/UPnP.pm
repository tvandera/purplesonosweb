package Sonos::UPnP;

require UPnP::ControlPoint;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( $DEBUG );

use Data::Dumper;


use constant SERVICE_TYPE =>  "urn:schemas-upnp-org:device:ZonePlayer:1";
use constant SERVICE_NAMES => qw(
    urn:schemas-upnp-org:service:ZoneGroupTopology:1
    urn:schemas-upnp-org:service:ContentDirectory:1
    urn:schemas-upnp-org:service:AVTransport:1
    urn:schemas-upnp-org:service:RenderingControl:1
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

###############################################################################
sub sonos_upnp_update {
    my ($service, %properties) = @_;

    Log (2, "Event received for service=" . $service->{BASE} . " id = " . $service->serviceId);
    Log(4, Dumper(\%properties));

    # Save off the zone names
    if ($service->serviceId =~ /serviceId:ZoneGroupTopology/) {
        foreach my $key (keys %properties) {
            if ($key eq "ZoneGroupState") {
                my $tree = XMLin(decode_entities($properties{$key}), forcearray => ["ZoneGroup", "ZoneGroupMember"]);
                Log(4, "ZoneGroupTopology " . Dumper($tree));
                my @groups = @{$tree->{ZoneGroups}->{ZoneGroup}};
                foreach my $group (@groups) {
                    my %zonegroup = %{$group};
                    my $coordinator = $zonegroup{Coordinator};
                    my @members = @{$zonegroup{ZoneGroupMember}};
                    $main::ZONES{$coordinator}->{Members} = [];

                    foreach my $member (@members) {
                        my $zkey = $member->{UUID};
                        foreach my $mkey (keys %{$member}) {
                            $main::ZONES{$zkey}->{$mkey} = $member->{$mkey};
                        }
                        $main::ZONES{$zkey}->{Coordinator} = $coordinator;
                        push @{ $main::ZONES{$coordinator}->{Members} }, $zkey;

                        my @ip = split(/\//, $member->{Location});
                        $main::ZONES{$zkey}->{IPPORT} = $ip[2];
                        $main::ZONES{$zkey}->{AV}->{LASTUPDATE} = 1 if (!defined $main::ZONES{$zkey}->{AV}->{LASTUPDATE});
                        $main::ZONES{$zkey}->{RENDER}->{LASTUPDATE} = 1 if (!defined $main::ZONES{$zkey}->{RENDER}->{LASTUPDATE});
                        $main::ZONES{$zkey}->{AV}->{CurrentTrackMetaData} = "" if (!defined $main::ZONES{$zkey}->{AV}->{CurrentTrackMetaData});
                        $main::QUEUEUPDATE{$zkey} = 1 if (!defined $main::QUEUEUPDATE{$zkey});
                    }
                }
                $main::LASTUPDATE  = $main::SONOS_UPDATENUM;
                $main::ZONESUPDATE = $main::SONOS_UPDATENUM++;

                sonos_process_waiting("ZONES");
            } elsif ($key eq "ThirdPartyMediaServers") {
                my $tree = XMLin(decode_entities($properties{$key}), forcearray => ["Service"]);
                for my $item ( @{ $tree->{Service} } ) {
                    if($item->{UDN} =~ "SA_RINCON1_") { #Rhapsody
                        Log(2, "Adding Rhapsody Subscription");
                        $main::SERVICES{Rhapsody} = $item;
                    } elsif($item->{UDN} =~ "SA_RINCON4_") { #PANDORA
                        Log(2, "Adding Pandora Subscription");
                        $main::SERVICES{Pandora} = $item;

                    } elsif($item->{UDN} =~ "SA_RINCON6_") { #SIRIUS
                        Log(2, "Adding Sirius Subscription");
                        $main::SERVICES{Sirius} = $item;
                    }
                }
                sonos_process_waiting("SERVICES");
            } else {
                Log(4, "$key " . Dumper($properties{$key}));
            }
        }
    }

    Log(4, "Parsed ZoneGroupTopology " . Dumper(\%main::ZONES));

    my $zone = sonos_location_to_id($service->{BASE});

    # Save off the current status
    if ($service->serviceId =~ /serviceId:RenderingControl/) {
        if (decode_entities($properties{LastChange}) eq "") {
            Log(3, "Unknown RenderingControl " . Dumper(\%properties));
            return;
        }
        my $tree = XMLin(decode_entities($properties{LastChange}),
                forcearray => ["ZoneGroup"],
                keyattr=>{"Volume"   => "channel",
                          "Mute"     => "channel",
                          "Loudness" => "channel"});
        Log(4, "RenderingControl " . Dumper($tree));
        foreach my $key ("Volume", "Treble", "Bass", "Mute", "Loudness") {
            if ($tree->{InstanceID}->{$key}) {
                $main::ZONES{$zone}->{RENDER}->{$key} = $tree->{InstanceID}->{$key};
                $main::LASTUPDATE                 = $main::SONOS_UPDATENUM;
                $main::ZONES{$zone}->{RENDER}->{LASTUPDATE} = $main::SONOS_UPDATENUM++;
            }
        }

        sonos_process_waiting("RENDER", $zone);

        return;
    }

    if ($service->serviceId =~ /serviceId:AVTransport/) {
        if (decode_entities($properties{LastChange}) eq "") {
            Log(3, "Unknown AVTransport " . Dumper(\%properties));
            return;
        }
        my $tree = XMLin(decode_entities($properties{LastChange}));
        Log(4, "AVTransport " . Dumper($tree));

        foreach my $key ("CurrentTrackMetaData", "CurrentPlayMode", "NumberOfTracks", "CurrentTrack", "TransportState", "AVTransportURIMetaData", "AVTransportURI", "r:NextTrackMetaData", "CurrentTrackDuration") {
            if ($tree->{InstanceID}->{$key}) {
                $main::LASTUPDATE             = $main::SONOS_UPDATENUM;
                $main::ZONES{$zone}->{AV}->{LASTUPDATE} = $main::SONOS_UPDATENUM++;
                if ($tree->{InstanceID}->{$key}->{val} =~ /^&lt;/) {
                    $tree->{InstanceID}->{$key}->{val} = decode_entities($tree->{InstanceID}->{$key}->{val});
                }
                if ($tree->{InstanceID}->{$key}->{val} =~ /^</) {
                    $main::ZONES{$zone}->{AV}->{$key} = \%{XMLin($tree->{InstanceID}->{$key}->{val})};
                } else {
                    $main::ZONES{$zone}->{AV}->{$key} = $tree->{InstanceID}->{$key}->{val};
                }
            }
        }

        sonos_process_waiting("AV", $zone);
        return;
    }


    if ($service->serviceId =~ /serviceId:ContentDirectory/) {
        Log(4, "ContentDirectory " . Dumper(\%properties));

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


    while (my ($key, $val) = each %properties) {
        if ($val =~ /&lt/) {
            my $d = decode_entities($val);
            my $tree = XMLin($d, forcearray => ["ZoneGroup"], keyattr=>{"ZoneGroup" => "ID"});
            Log(3, "Property ${key}'s value is " . Dumper($tree));
        } else {
            Log(3, "Property ${key}'s value is " . $val);
        }
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
        Log(4, "results = ", Dumper($results));
        my $tree = XMLin($results, forcearray => ["item", "container"], keyattr=>{});

        push(@data, @{$tree->{item}}) if (defined $tree->{item});
        push(@data, @{$tree->{container}}) if (defined $tree->{container});
    } while ($start < $result->getValue("TotalMatches"));

    return \@data;
}

###############################################################################
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