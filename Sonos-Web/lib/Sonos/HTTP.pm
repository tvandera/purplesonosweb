
###############################################################################
# HTTP
###############################################################################

%main::HTTP_HANDLERS = ();


###############################################################################
sub http_quit {
    $main::daemon->close();
}

###############################################################################
sub http_register_handler {
    my ( $path, $callback ) = @_;

    $main::HTTP_HANDLERS{$path} = $callback;
}

###############################################################################
sub http_albumart_request {
    my ( $c, $r ) = @_;

    my $uri = $r->uri;
    my %qf  = $uri->query_form;
    my $sha = sha256_hex($uri);
    my $text;

    delete $qf{zone}
      if ( exists $qf{zone} && !exists $main::ZONES{ $qf{zone} } );

    if ( defined $main::AACACHE{$sha} ) {
        $text = $main::AACACHE{$sha};
    }
    else {
        my @zones    = keys(%main::ZONES);
        my $zone     = $main::ZONES{ $zones[0] }->{Coordinator};
        my $ipport   = $main::ZONES{$zone}->{IPPORT};
        my $request  = "http://$ipport" . $uri;
        my $response = $main::useragent->get($request);
        my $image    = Image::Magick->new();

        if ( $response->is_success() ) {
            $image->Read( blob => $response->content );
            $image->Set( 'quality' => '80' );
            $image->Resize( 'width' => 200, 'height' => 200 );
            ($text) = $image->ImageToBlob( "filename" => "dummy.jpg" );
            $main::AACACHE{$sha} = $text;
        }
        else {
            Log( 3, "error for " . $uri );
            $image->Set( size => '200x200' );
            $image->ReadImage('canvas:black');
            ($text) = $image->ImageToBlob( "filename" => "dummy.jpg" );
        }
    }

    my $response =
      HTTP::Response->new( 200, undef, [ "Content-Type" => "image/jpg" ],
        $text );
    $c->send_response($response);
    $c->force_last_request;
}
###############################################################################
sub http_base_url {
    my ($r) = @_;

    my $baseurl;

    if ( !defined $r || !$r->header("host") ) {
        $baseurl =
            "http://"
          . UPnP::Common::getLocalIPAddress() . ":"
          . $main::HTTP_PORT;
    }
    else {
        $baseurl = "http://" . $r->header("host");
    }

    return $baseurl;
}
###############################################################################
sub http_check_password {
    my ( $c, $r ) = @_;

    if ( $main::PASSWORD ne "" ) {
        my $auth    = $r->header("Authorization");
        my $senderr = 1;
        if ( defined $auth && $auth =~ /Basic +(.*)/ ) {
            my ( $name, $pass ) = split( /:/, decode_base64($1) );
            $senderr = 0 if ( $main::PASSWORD eq $pass );
        }

        if ($senderr) {
            my $response = HTTP::Response->new(
                401, undef,
                [ "WWW-Authenticate" => "Basic realm=\"SonosWeb\"" ],
                "Please provide correct password"
            );
            Log( 3, "Sending response to " . $r->url );
            $c->send_response($response);
            $c->force_last_request;
            return 1;
        }
    }

    return 0;
}
###############################################################################
sub http_handle_request {
    my ( $c, $r ) = @_;

    # No r, just return
    if ( !$r || !$r->uri ) {
        Log( 1, "Missing Request" );
        return;
    }

    my $uri = $r->uri;

    my $path    = $uri->path;
    my $baseurl = http_base_url($r);

    if ( ( $path eq "/" ) || ( $path =~ /\.\./ ) ) {
        $c->send_redirect("$baseurl/$main::DEFAULT");
        $c->force_last_request;
        return;
    }

    my %qf = $uri->query_form;
    delete $qf{zone}
      if ( exists $qf{zone} && !exists $main::ZONES{ $qf{zone} } );

    if ( $main::HTTP_HANDLERS{$path} ) {
        my $callback = $main::HTTP_HANDLERS{$path};
        &$callback( $c, $r );
        return;
    }

    # Find where on disk
    my $diskpath;
    my $tmplhook;
    if ( -e "html/$path" ) {
        $diskpath = "html$path";
    }
    else {
        my @parts  = split( "/", $path );
        my $plugin = $parts[1];
        splice( @parts, 0, 2 );
        my $restpath = join( "/", @parts );
        if (   $main::PLUGINS{$plugin}
            && $main::PLUGINS{$plugin}->{html}
            && -e $main::PLUGINS{$plugin}->{html} . $restpath )
        {
            $diskpath = $main::PLUGINS{$plugin}->{html} . $restpath;
            $tmplhook = $main::PLUGINS{$plugin}->{tmplhook};
        }
    }

    # File doesn't exist
    if ( !$diskpath ) {
        $c->send_error(HTTP::Status::RC_NOT_FOUND);
        $c->force_last_request;
        return;
    }

    # File is a directory, redirect for the browser
    if ( -d $diskpath ) {
        if ( $path =~ /\/$/ ) {
            $c->send_redirect( $baseurl . $path . "index.html" );
        }
        else {
            $c->send_redirect( $baseurl . $path . "/index.html" );
        }
        $c->force_last_request;
        return;
    }

    # File isn't HTML/XML/JSON, just send it back raw
    if (   !( $path =~ /\.html/ )
        && !( $path =~ /\.xml/ )
        && !( $path =~ /\.json/ ) )
    {
        $c->send_file_response($diskpath);
        $c->force_last_request;
        return;
    }

# 0 - not handled, 1 - handled send reply, >= 2 - handled routine will send reply
    my $response = 0;

    if ( exists $qf{action} ) {
        return if ( http_check_password( $c, $r ) );

        if ( exists $qf{zone} ) {
            $response = http_handle_zone_action( $c, $r, $path );
        }
        if ( !$response ) {
            $response = http_handle_action( $c, $r, $path );
        }
    }

    if ( $qf{NoWait} ) {
        $response = 1;
    }

    if ( $response == 2 ) {
        sonos_add_waiting( "AV", "*", \&http_send_tmpl_response, $c, $r,
            $diskpath, $tmplhook );
    }
    elsif ( $response == 3 ) {
        sonos_add_waiting( "RENDER", "*", \&http_send_tmpl_response, $c, $r,
            $diskpath, $tmplhook );
    }
    elsif ( $response == 4 ) {
        sonos_add_waiting( "QUEUE", "*", \&http_send_tmpl_response, $c, $r,
            $diskpath, $tmplhook );
    }
    elsif ( $response == 5 ) {
        sonos_add_waiting( "*", "*", \&http_send_tmpl_response, $c, $r,
            $diskpath, $tmplhook );
    }
    else {
        http_send_tmpl_response( "*", "*", $c, $r, $diskpath, $tmplhook );
    }

}

###############################################################################
sub http_handle_zone_action {
    my ( $c, $r, $path ) = @_;

    my %qf = $r->uri->query_form;
    delete $qf{zone}
      if ( exists $qf{zone} && !exists $main::ZONES{ $qf{zone} } );
    my $mpath = decode( "UTF-8", $qf{mpath} );

    my $zone = $qf{zone};
    if ( $qf{action} eq "Remove" ) {
        upnp_avtransport_remove_track( $zone, $qf{queue} );
        return 4;
    }
    elsif ( $qf{action} eq "RemoveAll" ) {
        upnp_avtransport_action( $zone, "RemoveAllTracksFromQueue" );
        return 4;
    }
    elsif ( $qf{action} eq "Play" ) {
        if ( $main::ZONES{$zone}->{AV}->{TransportState} eq "PLAYING" ) {
            return 1;
        }
        else {
            upnp_avtransport_play($zone);
            return 2;
        }
    }
    elsif ( $qf{action} eq "Pause" ) {
        if ( $main::ZONES{$zone}->{AV}->{TransportState} eq "PAUSED_PLAYBACK" )
        {
            return 1;
        }
        else {
            upnp_avtransport_action( $zone, $qf{action} );
            return 2;
        }
    }
    elsif ( $qf{action} eq "Stop" ) {
        if ( $main::ZONES{$zone}->{AV}->{TransportState} eq "STOPPED" ) {
            return 1;
        }
        else {
            upnp_avtransport_action( $zone, $qf{action} );
            return 2;
        }
    }
    elsif ( $qf{action} =~ /(Next|Previous)/ ) {
        upnp_avtransport_action( $zone, $qf{action} );
        return 2;
    }
    elsif ( $qf{action} eq "ShuffleOn" ) {
        upnp_avtransport_shuffle( $zone, 1 );
        return 1;
    }
    elsif ( $qf{action} eq "ShuffleOff" ) {
        upnp_avtransport_shuffle( $zone, 0 );
        return 1;
    }
    elsif ( $qf{action} eq "RepeatOn" ) {
        upnp_avtransport_repeat( $zone, 1 );
        return 1;
    }
    elsif ( $qf{action} eq "RepeatOff" ) {
        upnp_avtransport_repeat( $zone, 0 );
        return 1;
    }
    elsif ( $qf{action} eq "Seek" ) {
        if ( !( $main::ZONES{$zone}->{AV}->{AVTransportURI} =~ /queue/ ) ) {
            sonos_avtransport_set_queue($zone);
        }
        upnp_avtransport_seek( $zone, $qf{queue} );
        return 2;
    }
    elsif ( $qf{action} eq "MuteOn" ) {
        upnp_render_mute( $zone, 1 );
        return 3;
    }
    elsif ( $qf{action} eq "MuteOff" ) {
        upnp_render_mute( $zone, 0 );
        return 3;
    }
    elsif ( $qf{action} eq "MuchSofter" ) {
        upnp_render_volume_change( $zone, -5 );
        return 3;
    }
    elsif ( $qf{action} eq "Softer" ) {
        upnp_render_volume_change( $zone, -1 );
        return 3;
    }
    elsif ( $qf{action} eq "Louder" ) {
        upnp_render_volume_change( $zone, +1 );
        return 3;
    }
    elsif ( $qf{action} eq "MuchLouder" ) {
        upnp_render_volume_change( $zone, +5 );
        return 3;
    }
    elsif ( $qf{action} eq "SetVolume" ) {
        upnp_render_volume( $zone, $qf{volume} );
        return 3;
    }
    elsif ( $qf{action} eq "Save" ) {
        upnp_avtransport_save( $zone, $qf{savename} );
        return 0;
    }
    elsif ( $qf{action} eq "AddMusic" ) {
        my $class = sonos_music_class($mpath);
        if ( sonos_is_radio($mpath) ) {
            sonos_avtransport_set_radio( $zone, $mpath );
            return 2;
        }
        elsif ( $class eq "object.item.audioItem" ) {
            sonos_avtransport_set_linein( $zone, $mpath );
            return 2;
        }
        else {
            sonos_avtransport_add( $zone, $mpath );
            return 4;
        }
    }
    elsif ( $qf{action} eq "DeleteMusic" ) {
        if ( sonos_music_class($mpath) eq "object.container.playlist" ) {
            my $entry = sonos_music_entry($mpath);
            upnp_content_dir_delete( $zone, $entry->{id} );
        }
        return 0;
    }
    elsif ( $qf{action} eq "PlayMusic" ) {
        my $class = sonos_music_class($mpath);
        if ( sonos_is_radio($mpath) ) {
            sonos_avtransport_set_radio( $zone, $mpath );
        }
        elsif ( $class eq "object.item.audioItem" ) {
            sonos_avtransport_set_linein( $zone, $mpath );
        }
        else {
            if ( !( $main::ZONES{$zone}->{AV}->{AVTransportURI} =~ /queue/ ) ) {
                sonos_avtransport_set_queue($zone);
            }
            upnp_avtransport_action( $zone, "RemoveAllTracksFromQueue" );
            sonos_avtransport_add( $zone, $mpath );
            upnp_avtransport_play($zone);
        }

        return 4;
    }
    elsif ( $qf{action} eq "LinkAll" ) {
        sonos_link_all_zones($zone);
        return 2;
    }
    elsif ( $qf{action} eq "Unlink" ) {
        sonos_unlink_zone( $qf{link} );
        return 2;
    }
    elsif ( $qf{action} eq "Link" ) {
        sonos_link_zone( $zone, $qf{link} );
    }
    else {
        return 0;
    }
    return 1;
}

###############################################################################
sub http_handle_action {
    my ( $c, $r, $path ) = @_;

    my %qf = $r->uri->query_form;
    delete $qf{zone}
      if ( exists $qf{zone} && !exists $main::ZONES{ $qf{zone} } );

    if ( $qf{action} eq "ReIndex" ) {
        sonos_reindex();
    }
    elsif ( $qf{action} eq "Unlink" ) {
        sonos_unlink_zone( $qf{link} );
    }
    elsif ( $qf{action} eq "Wait" && $qf{lastupdate} ) {
        if ( $main::LASTUPDATE > $qf{lastupdate} ) {
            return 1;
        }
        else {
            return 5;
        }
    }
    else {
        return 0;
    }
    return 1;
}

###############################################################################
sub http_build_zone_data {
    my ( $zone, $updatenum, $active_zone ) = @_;
    my %activedata;

    $activedata{HAS_ACTIVE_ZONE} = int( defined $active_zone );
    $activedata{ACTIVE_ZONE}     = enc( $main::ZONES{$zone}->{ZoneName} );
    $activedata{ACTIVE_ZONEID}   = uri_escape($zone);
    $activedata{ACTIVE_VOLUME} =
      int( $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val} );
    $activedata{ZONE_ACTIVE} =
      defined $active_zone && int( $zone eq $active_zone );

    my $lastupdate;
    if ( $main::ZONES{$zone}->{RENDER}->{LASTUPDATE} >
        $main::ZONES{$zone}->{AV}->{LASTUPDATE} )
    {
        $lastupdate = $main::ZONES{$zone}->{RENDER}->{LASTUPDATE};
    }
    else {
        $lastupdate = $main::ZONES{$zone}->{AV}->{LASTUPDATE};
    }

    $activedata{ACTIVE_LASTUPDATE} = $lastupdate;
    $activedata{ACTIVE_UPDATED}    = ( $lastupdate > $updatenum );

    if ( $main::ZONES{$zone}->{RENDER}->{Mute}->{Master}->{val} ) {
        $activedata{ACTIVE_MUTED} = 1;
    }
    else {
        $activedata{ACTIVE_MUTED} = 0;
    }

    my $curtrack     = $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData};
    my $curtransport = $main::ZONES{$zone}->{AV}->{AVTransportURIMetaData};

    $activedata{ACTIVE_NAME}           = "";
    $activedata{ACTIVE_ARTIST}         = "";
    $activedata{ACTIVE_ALBUM}          = "";
    $activedata{ACTIVE_ISSONG}         = 1;
    $activedata{ACTIVE_ISRADIO}        = 0;
    $activedata{ACTIVE_TRACK_NUM}      = 0;
    $activedata{ACTIVE_TRACK_TOT}      = 0;
    $activedata{ACTIVE_TRACK_TOT_0}    = 0;
    $activedata{ACTIVE_TRACK_TOT_1}    = 0;
    $activedata{ACTIVE_TRACK_TOT_GT_1} = 0;
    $activedata{ACTIVE_MODE}           = 0;
    $activedata{ACTIVE_PAUSED}         = 0;
    $activedata{ACTIVE_STOPPED}        = 0;
    $activedata{ACTIVE_PLAYING}        = 0;
    $activedata{ACTIVE_SHUFFLE}        = 0;
    $activedata{ACTIVE_REPEAT}         = 0;
    $activedata{ACTIVE_LENGTH}         = 0;
    $activedata{ACTIVE_ALBUMART}       = "";
    $activedata{ACTIVE_CONTENT}        = "";

    if ($curtrack) {
        if ( $curtrack->{item}->{res}{content} ) {
            $activedata{ACTIVE_CONTENT} = $curtrack->{item}->{res}{content};
        }

        if ( $curtrack->{item}->{"upnp:albumArtURI"} ) {
            $activedata{ACTIVE_ALBUMART} =
              $curtrack->{item}->{"upnp:albumArtURI"};
        }

        if (   $curtransport
            && $curtransport->{item}->{"upnp:class"} eq
            "object.item.audioItem.audioBroadcast" )
        {
            if ( !ref( $curtrack->{item}->{"r:streamContent"} ) ) {
                $activedata{ACTIVE_NAME} =
                  enc( $curtrack->{item}->{"r:streamContent"} );
            }

            if ( !defined( $curtrack->{item}->{"dc:creator"} ) ) {
                $activedata{ACTIVE_ALBUM} =
                  enc( $curtransport->{item}->{"dc:title"} );
            }
            else {
                $activedata{ACTIVE_NAME} =
                  enc( $curtrack->{item}->{"dc:title"} );
                $activedata{ACTIVE_ARTIST} =
                  enc( $curtrack->{item}->{"dc:creator"} );
                $activedata{ACTIVE_ALBUM} =
                  enc( $curtrack->{item}->{"upnp:album"} );
                $activedata{ACTIVE_TRACK_NUM} = -1;
                $activedata{ACTIVE_TRACK_TOT} =
                  $curtransport->{item}->{"dc:title"} . " \/";
            }

            $activedata{ACTIVE_ISSONG}  = 0;
            $activedata{ACTIVE_ISRADIO} = 1;
        }
        else {

            $activedata{ACTIVE_NAME} = enc( $curtrack->{item}->{"dc:title"} );
            $activedata{ACTIVE_ARTIST} =
              enc( $curtrack->{item}->{"dc:creator"} );
            $activedata{ACTIVE_ALBUM} =
              enc( $curtrack->{item}->{"upnp:album"} );
            $activedata{ACTIVE_TRACK_NUM} =
              $main::ZONES{$zone}->{AV}->{CurrentTrack};
            $activedata{ACTIVE_TRACK_TOT} =
              $main::ZONES{$zone}->{AV}->{NumberOfTracks};
            $activedata{ACTIVE_TRACK_TOT_0} =
              ( $main::ZONES{$zone}->{AV}->{NumberOfTracks} == 0 );
            $activedata{ACTIVE_TRACK_TOT_1} =
              ( $main::ZONES{$zone}->{AV}->{NumberOfTracks} == 1 );
            $activedata{ACTIVE_TRACK_TOT_GT_1} =
              ( $main::ZONES{$zone}->{AV}->{NumberOfTracks} > 1 );
        }
        if ( $main::ZONES{$zone}->{AV}->{TransportState} eq "PAUSED_PLAYBACK" )
        {
            $activedata{ACTIVE_MODE}   = 2;
            $activedata{ACTIVE_PAUSED} = 1;
        }
        elsif ( $main::ZONES{$zone}->{AV}->{TransportState} eq "STOPPED" ) {
            $activedata{ACTIVE_MODE}    = 0;
            $activedata{ACTIVE_STOPPED} = 1;
        }
        else {
            $activedata{ACTIVE_MODE}    = 1;
            $activedata{ACTIVE_PLAYING} = 1;
        }

        if ( $main::ZONES{$zone}->{AV}->{CurrentPlayMode} eq "NORMAL" ) {
        }
        elsif ( $main::ZONES{$zone}->{AV}->{CurrentPlayMode} eq "REPEAT_ALL" ) {
            $activedata{ACTIVE_REPEAT} = 1;
        }
        elsif (
            $main::ZONES{$zone}->{AV}->{CurrentPlayMode} eq "SHUFFLE_NOREPEAT" )
        {
            $activedata{ACTIVE_SHUFFLE} = 1;
        }
        elsif ( $main::ZONES{$zone}->{AV}->{CurrentPlayMode} eq "SHUFFLE" ) {
            $activedata{ACTIVE_SHUFFLE} = 1;
            $activedata{ACTIVE_REPEAT}  = 1;
        }
    }

    if ( $main::ZONES{$zone}->{AV}->{CurrentTrackDuration} ) {
        my @parts =
          split( ":", $main::ZONES{$zone}->{AV}->{CurrentTrackDuration} );
        $activedata{ACTIVE_LENGTH} =
          $parts[0] * 3600 + $parts[1] * 60 + $parts[2];
    }

    my $nexttrack = $main::ZONES{$zone}->{AV}->{"r:NextTrackMetaData"};
    if ($nexttrack) {
        $activedata{NEXT_NAME}   = enc( $nexttrack->{item}->{"dc:title"} );
        $activedata{NEXT_ARTIST} = enc( $nexttrack->{item}->{"dc:creator"} );
        $activedata{NEXT_ALBUM}  = enc( $nexttrack->{item}->{"upnp:album"} );
        $activedata{NEXT_ISSONG} = 1;
    }

    $activedata{ZONE_MODE}   = $activedata{ACTIVE_MODE};
    $activedata{ZONE_MUTED}  = $activedata{ACTIVE_MUTED};
    $activedata{ZONE_ID}     = $activedata{ACTIVE_ZONEID};
    $activedata{ZONE_NAME}   = $activedata{ACTIVE_ZONE};
    $activedata{ZONE_VOLUME} = $activedata{ACTIVE_VOLUME};
    $activedata{ZONE_ARG}    = "zone=" . uri_escape_utf8($zone) . "&";

    my $icon = $main::ZONES{$zone}->{Icon};
    $icon =~ s/^x-rincon-roomicon://;
    $activedata{ZONE_ICON} = $icon;

    $activedata{ZONE_LASTUPDATE} = $lastupdate;
    my $num_linked = $#{ $main::ZONES{$zone}->{Members} };
    $activedata{ZONE_NUMLINKED} = $num_linked;
    $activedata{ZONE_FANCYNAME} = $activedata{ZONE_NAME};
    $activedata{ZONE_FANCYNAME} .= " + " . $num_linked if $num_linked;

    my @members;
    foreach ( @{ $main::ZONES{$zone}->{Members} } ) {
        my %memberdata;
        $memberdata{"ZONE_NAME"} = $main::ZONES{$_}->{ZoneName};
        $memberdata{"ZONE_ID"}   = $_;
        $memberdata{"ZONE_LINKED"} =
          int( $main::ZONES{$_}->{Coordinator} ne $_ );
        $memberdata{"ZONE_ICON"} = $main::ZONES{$_}->{Icon};
        $memberdata{"ZONE_ICON"} =~ s/^x-rincon-roomicon://;
        push @members, \%memberdata;
    }
    $activedata{ZONE_MEMBERS} = \@members;

    if ( $main::ZONES{$zone}->{Coordinator} eq $zone ) {
        $activedata{ZONE_LINKED}    = 0;
        $activedata{ZONE_LINK}      = "";
        $activedata{ZONE_LINK_NAME} = "";
    }
    else {
        $activedata{ZONE_LINKED} = 1;
        $activedata{ZONE_LINK}   = $main::ZONES{$zone}->{Coordinator};
        $activedata{ZONE_LINK_NAME} =
          enc( $main::ZONES{ $main::ZONES{$zone}->{Coordinator} }->{ZoneName} );
    }

    $activedata{ACTIVE_JSON} = to_json( \%activedata, { pretty => 1 } );

    return \%activedata;
}

###############################################################################
sub http_build_queue_data {
    my ( $zone, $updatenum ) = @_;

    my %queuedata;

    $queuedata{QUEUE_ZONE}       = enc( $main::ZONES{$zone}->{ZoneName} );
    $queuedata{QUEUE_ZONEID}     = uri_escape_utf8($zone);
    $queuedata{QUEUE_LASTUPDATE} = $main::QUEUEUPDATE{$zone};
    $queuedata{QUEUE_UPDATED}    = ( $main::QUEUEUPDATE{$zone} > $updatenum );

    my $i         = 1;
    my @loop_data = ();
    my $q         = $main::ZONES{$zone}->{QUEUE};
    $q = () unless $q;

    foreach my $queue (@$q) {
        my %row_data;
        my $av      = $main::ZONES{$zone}->{AV};
        my $playing = ( $av->{TransportState} eq "PLAYING" );

        $row_data{QUEUE_NAME}   = enc( $queue->{"dc:title"} );
        $row_data{QUEUE_ALBUM}  = enc( $queue->{"upnp:album"} );
        $row_data{QUEUE_ARTIST} = enc( $queue->{"dc:creator"} );
        $row_data{QUEUE_TRACK_NUM} =
          enc( $queue->{"upnp:originalTrackNumber"} );
        $row_data{QUEUE_ALBUMART} = enc( $queue->{"upnp:albumArtURI"} );
        $row_data{QUEUE_ARG}      = "zone="
          . uri_escape_utf8($zone)
          . "&queue="
          . uri_escape_utf8( $queue->{id} );
        $row_data{QUEUE_ID} = $queue->{id};
        push( @loop_data, \%row_data );
        $i++;
    }

    $queuedata{QUEUE_LOOP} = \@loop_data;
    $queuedata{QUEUE_JSON} = to_json( \@loop_data, { pretty => 1 } );

    return \%queuedata;
}

sub http_build_music_data {
    my $qf        = shift;
    my $updatenum = shift;
    my %musicdata;

    my @music_loop_data = ();
    my @page_loop_data  = ();
    my $firstsearch     = ( $qf->{firstsearch} ? $qf->{firstsearch} : 0 );
    my $maxsearch       = $main::MAX_SEARCH;
    $maxsearch = $qf->{maxsearch} if ( $qf->{maxsearch} );

    my $albumart = "";

    my $mpath = "";
    $mpath = $qf->{mpath} if ( defined $qf->{mpath} );
    $mpath = ""           if ( $mpath eq "/" );
    my $msearch = $qf->{msearch};
    my $item    = sonos_music_entry($mpath);
    my $name    = enc( $item->{'dc:title'} );

    $musicdata{"MUSIC_ROOT"}       = int( $mpath eq "" );
    $musicdata{"MUSIC_LASTUPDATE"} = $main::MUSICUPDATE;
    $musicdata{"MUSIC_PATH"}       = enc($mpath);
    $musicdata{"MUSIC_NAME"}       = enc( $item->{'dc:title'} );
    $musicdata{"MUSIC_ARTIST"}     = enc( $item->{'dc:creator'} );
    $musicdata{"MUSIC_ALBUM"}      = enc( $item->{'upnp:album'} );
    $musicdata{"MUSIC_UPDATED"}    = ( $mpath ne ""
          || ( !$qf->{NoWait} && ( $main::MUSICUPDATE > $updatenum ) ) );
    $musicdata{"MUSIC_PARENT"} = uri_escape_utf8( $item->{parentID} )
      if ( defined $item && defined $item->{parentID} );
    my $music_arg = $musicdata{MUSIC_ARG} = "mpath=" . uri_escape_utf8($mpath);

    my $class = $item->{'upnp:class'};
    $musicdata{"MUSIC_CLASS"} = enc($class);

    $musicdata{MUSIC_ISSONG}  = int( $class =~ /musicTrack$/ );
    $musicdata{MUSIC_ISRADIO} = int( $class =~ /audioBroadcast$/ );
    $musicdata{MUSIC_ISALBUM} = int( $class =~ /musicAlbum$/ );

    my $elements = sonos_containers_get( $mpath, $item );

    $musicdata{MUSIC_ISPAGED} = int( scalar @{$elements} > $maxsearch )
      if $elements;
    my $from            = "";
    my $to              = "";
    my $count           = 0;
    my $has_non_letters = 0;
    foreach my $music ( @{$elements} ) {
        my $name   = $music->{"dc:title"};
        my $letter = uc( substr( $name, 0, 1 ) );
        $from = $letter unless $from;
        $count++;

        if ( ( $count > $maxsearch ) && ( $letter ne $to ) ) {
            my %data;
            $data{PAGE_NAME} = enc("$from-$to") unless ( $from eq $to );
            $data{PAGE_NAME} = enc($from) if ( $from eq $to );
            $data{PAGE_ARG} =
                "$music_arg&from="
              . uri_escape_utf8($from) . "&to="
              . uri_escape_utf8($to);
            push @page_loop_data, \%data;
            $count = 0;
            $from  = $letter;
        }

        $to = $letter;
    }

    # last
    my %data;
    $data{PAGE_NAME} = enc("$from-$to") unless ( $from eq $to );
    $data{PAGE_NAME} = enc($from) if ( $from eq $to );
    $data{PAGE_ARG} =
        "$music_arg&from="
      . uri_escape_utf8($from) . "&to="
      . uri_escape_utf8($to);
    push @page_loop_data, \%data;
    $musicdata{"PAGE_LOOP"} = \@page_loop_data;

    $from = decode( 'utf8', $qf->{from} );
    $to   = decode( 'utf8', $qf->{to} );
    foreach my $music ( @{$elements} ) {
        my %row_data;

        my $class     = $music->{"upnp:class"};
        my $realclass = sonos_music_realclass($music);
        my $name      = $music->{"dc:title"};
        my $letter    = uc( substr( $name, 0, 1 ) );
        next if ( $msearch && $name !~ m/$msearch/i );
        next if ( $from    && $letter lt $from );
        next if ( $to      && $letter gt $to );

        $row_data{MUSIC_NAME}      = enc($name);
        $row_data{MUSIC_CLASS}     = enc($class);
        $row_data{MUSIC_PATH}      = enc( $music->{id} );
        $row_data{MUSIC_REALCLASS} = enc($realclass);
        $row_data{MUSIC_ARG}       = "mpath=" . uri_escape_utf8( $music->{id} );
        $row_data{"MUSIC_ALBUMART"}  = sonos_music_albumart($music);
        $musicdata{"MUSIC_ALBUMART"} = $row_data{"MUSIC_ALBUMART"}
          unless $musicdata{"MUSIC_ALBUMART"};
        $row_data{"MUSIC_ALBUM"}  = enc( $music->{"upnp:album"} );
        $row_data{"MUSIC_ARTIST"} = enc( $music->{"dc:creator"} );
        $row_data{"MUSIC_DESC"}   = enc( $music->{"r:description"} );
        $row_data{MUSIC_TRACK_NUM} =
          enc( $music->{"upnp:originalTrackNumber"} );

        $row_data{MUSIC_ISFAV}   = int( $class     =~ /favorite$/ );
        $row_data{MUSIC_ISSONG}  = int( $realclass =~ /musicTrack$/ );
        $row_data{MUSIC_ISRADIO} = int( $realclass =~ /audioBroadcast$/ );
        $row_data{MUSIC_ISALBUM} = int( $realclass =~ /musicAlbum$/ );

        push( @music_loop_data, \%row_data );
        last if ( !$from && $#music_loop_data > $firstsearch + $maxsearch );
    }

    splice( @music_loop_data, 0, $firstsearch ) if ( $firstsearch > 0 );
    if ( $#music_loop_data > $maxsearch ) {
        $musicdata{"MUSIC_ERROR"} = "More then $maxsearch matching items.<BR>";
    }

    $musicdata{"MUSIC_LOOP"} = \@music_loop_data;

    return \%musicdata;
}
###############################################################################
# Sort items by coordinators first, for linked zones sort under their coordinator
sub http_zone_sort_linked () {
    my $c = $main::ZONES{ $main::ZONES{$main::a}->{Coordinator} }->{ZoneName}
      cmp $main::ZONES{ $main::ZONES{$main::b}->{Coordinator} }->{ZoneName};
    return $c if ( $c != 0 );
    return -1 if ( $main::ZONES{$main::a}->{Coordinator} eq $main::a );
    return 1  if ( $main::ZONES{$main::b}->{Coordinator} eq $main::b );
    return $main::ZONES{$main::a}->{ZoneName}
      cmp $main::ZONES{$main::b}->{ZoneName};
}
###############################################################################
# Sort items by coordinators first, for linked zones sort under their coordinator
sub http_zone_sort () {
    return $main::ZONES{$main::a}->{ZoneName}
      cmp $main::ZONES{$main::b}->{ZoneName};
}

###############################################################################
sub http_zones {
    my ($linked) = @_;

    my @zkeys =
      grep ( !exists $main::ZONES{$_}->{Invisible}, keys %main::ZONES );

    if ( defined $linked && $linked ) {
        return ( sort http_zone_sort_linked(@zkeys) );
    }
    else {
        return ( sort http_zone_sort(@zkeys) );
    }
}

###############################################################################
sub http_build_map {
    my ( $qf, $params ) = @_;

    my $updatenum = 0;
    $updatenum = $qf->{lastupdate} if ( $qf->{lastupdate} );

    my %map = ();

    # globals
    {
        my $globals = {};
        my $host = UPnP::Common::getLocalIPAddress() . ":" . $main::HTTP_PORT;
        $globals->{"BASE_URL"}             = "http://$host";
        $globals->{"VERSION"}              = $main::VERSION;
        $globals->{"LAST_UPDATE"}          = $main::LASTUPDATE;
        $globals->{"LAST_UPDATE_READABLE"} = localtime $main::LASTUPDATE;

        my @keys    = grep !/action|rand|mpath|msearch|link/, ( keys %$qf );
        my $all_arg = "";
        $all_arg .= "$_=$qf->{$_}&" for @keys;
        $globals->{"ALL_ARG"} = $all_arg;

        $globals->{"MUSICDIR_AVAILABLE"} = !( $main::MUSICDIR eq "" );
        $globals->{"ZONES_LASTUPDATE"}   = $main::ZONESUPDATE;
        $globals->{"ZONES_UPDATED"}      = ( $main::ZONESUPDATE > $updatenum );

        $map{GLOBALS_JSON} =
          to_json( $globals, { pretty => 1 }, { pretty => 1 } );
        %map = ( %map, %$globals );
    }

    if ( grep /^ZONES_/i, @$params ) {
        my @zones = map { http_build_zone_data( $_, $updatenum, $qf->{zone} ); }
          main::http_zones(1);
        $map{ZONES_LOOP} = \@zones;
        $map{ZONES_JSON} = to_json( \@zones, { pretty => 1 } );
    }

    if ( grep /^ALL_QUEUE_/i, @$params ) {
        my @queues =
          map { http_build_queue_data( $_, $updatenum ); } main::http_zones(1);
        $map{ALL_QUEUE_LOOP} = \@queues;
        $map{ALL_QUEUE_JSON} = to_json( \@queues, { pretty => 1 } );
    }

    if ( exists $qf->{zone} ) {
        my $queue = http_build_queue_data( $qf->{zone}, $updatenum );
        $map{QUEUE_JSON} = to_json( $queue, { pretty => 1 } );
        %map = ( %map, %$queue );
    }

    if ( grep /^MUSIC_/i, @$params ) {
        my $music = http_build_music_data( $qf, $updatenum );
        $map{MUSIC_JSON} = to_json( $music, { pretty => 1 } );
        %map = ( %map, %$music );
    }

    if ( exists $qf->{zone} ) {
        my $zone = http_build_zone_data( $qf->{zone}, $updatenum, $qf->{zone} );
        %map = ( %map, %$zone );
    }

    if ( grep /^PLUGIN_/i, @$params ) {
        my @loop_data = ();

        foreach my $plugin ( sort ( keys %main::PLUGINS ) ) {
            next if ( !$main::PLUGINS{$plugin}->{link} );
            my %row_data;
            $row_data{PLUGIN_LINK} = $main::PLUGINS{$plugin}->{link};
            $row_data{PLUGIN_NAME} = $main::PLUGINS{$plugin}->{name};

            push( @loop_data, \%row_data );
        }

        $map{"PLUGIN_LOOP"} = \@loop_data;
        $map{"PLUGIN_JZON"} = to_json( \@loop_data, { pretty => 1 } );
    }

    # Log(4, "\nParams = " . Dumper($params));
    # Log(4, "\nData = " . Dumper(\%map) . "\n");

    return \%map;

}

###############################################################################
sub http_send_tmpl_response {
    my ( $what, $zone, $c, $r, $diskpath, $tmplhook ) = @_;

    my %qf = $r->uri->query_form;
    delete $qf{zone}
      if ( exists $qf{zone} && !exists $main::ZONES{ $qf{zone} } );

    # One of ours templates, now fill in the parts we know
    my $template = HTML::Template::Compiled->new(
        filename          => $diskpath,
        die_on_bad_params => 0,
        global_vars       => 1,
        use_query         => 1,
        loop_context_vars => 1
    );
    my @params = $template->param();
    my $map    = http_build_map( \%qf, \@params );
    $template->param(%$map);

    &$tmplhook( $c, $r, $diskpath, $template ) if ($tmplhook);

    my $content_type = "text/html; charset=ISO-8859-1";
    if ( $r->uri->path =~ /\.xml/ ) {
        $content_type = "text/xml; charset=ISO-8859-1";
    }
    if ( $r->uri->path =~ /\.json/ ) { $content_type = "application/json"; }

    my $output = encode( 'utf8', $template->output );
    my $gzoutput;
    my $status   = gzip \$output => \$gzoutput;
    my $response = HTTP::Response->new(
        200, undef,
        [
            Connection         => "close",
            "Content-Type"     => $content_type,
            "Pragma"           => "no-cache",
            "Content-Encoding" => "gzip",
            "Cache-Control"    =>
              "no-store, no-cache, must-revalidate, post-check=0, pre-check=0"
        ],
        $gzoutput
    );
    $c->send_response($response);
    $c->force_last_request;
    $c->close;
}
