
###############################################################################
sub sonos_mkcontainer {
    my ($parent, $class, $title, $id, $icon, $content) = @_;

    my %data;

    $data{'upnp:class'}       = $class;
    $data{'dc:title'}         = $title;
    $data{parentID}           = $parent;
    $data{id}                 = $id;
    $data{'upnp:albumArtURI'} = $icon;
    $data{res}->{content}     = $content if (defined $content);

    push (@{$main::CONTAINERS{$parent}},  \%data);

    $main::ITEMS{$data{id}} = \%data;
}

###############################################################################
sub sonos_mkitem {
    my ($parent, $class, $title, $id, $content) = @_;

    $main::ITEMS{$id}->{"upnp:class"}   = $class;
    $main::ITEMS{$id}->{parentID}       = $parent;
    $main::ITEMS{$id}->{"dc:title"}     = $title;
    $main::ITEMS{$id}->{id}             = $id;
    $main::ITEMS{$id}->{res}->{content} = $content if (defined $content);
}
###############################################################################
sub sonos_containers_init {

    $main::MUSICUPDATE = $main::SONOS_UPDATENUM++;

    undef %main::CONTAINERS;

    sonos_mkcontainer("", "object.container", "Favorites", "FV:2", "tiles/favorites.svg");
    sonos_mkcontainer("", "object.container", "Artists", "A:ARTIST", "tiles/artists.svg");
    sonos_mkcontainer("", "object.container", "Albums", "A:ALBUM", "tiles/album.svg");
    sonos_mkcontainer("", "object.container", "Genres", "A:GENRE", "tiles/genre.svg");
    sonos_mkcontainer("", "object.container", "Composers", "A:COMPOSER", "tiles/composers.svg");
    sonos_mkcontainer("", "object.container", "Tracks", "A:TRACKS", "tiles/track.svg");
    #sonos_mkcontainer("", "object.container", "Imported Playlists", "A:PLAYLISTS", "tiles/playlist.svg");
    #sonos_mkcontainer("", "object.container", "Folders", "S:", "tiles/folder.svg");
    sonos_mkcontainer("", "object.container", "Radio", "R:0/0", "tiles/radio_logo.svg");
    # sonos_mkcontainer("", "object.container", "Line In", "AI:", "tiles/linein.svg");
    # sonos_mkcontainer("", "object.container", "Playlists", "SQ:", "tiles/sonos_playlists.svg");

    sonos_mkitem("", "object.container", "Music", "");
}
###############################################################################
sub sonos_containers_get {
    my ($what, $item) = @_;

    my ($zone) = split(",", $main::UPDATEID{ShareListUpdateID});
    if (!defined $zone) {
        my $foo = ();
        return $foo;
    }

    my $type = substr ($what, 0, index($what, ':'));

    if (defined $main::HOOK{"CONTAINER_$type"}) {
        sonos_process_hook("CONTAINER_$type", $what);
    }

    if (exists $main::CONTAINERS{$what}) {
        Log (2, "Using cache for $what");
    } elsif ($what eq "AI:") { # line-in
        $main::CONTAINERS{$what} = ();
        foreach my $zone (keys %main::ZONES) {
            my $linein =  upnp_content_dir_browse($zone, "AI:");

            if (defined $linein->[0]) {
                $linein->[0]->{id} .= "/" . $linein->[0]->{"dc:title"};
                push @{$main::CONTAINERS{$what}}, $linein->[0];
            }
        }
    } else {
        $main::CONTAINERS{$what} = upnp_content_dir_browse($zone, $what);
    }

    foreach my $item (@{$main::CONTAINERS{$what}}) {
        $main::ITEMS{$item->{id}} = $item;
    }
    return $main::CONTAINERS{$what};
}
###############################################################################
sub sonos_containers_del {
    my ($what) = @_;

    $main::MUSICUPDATE = $main::SONOS_UPDATENUM++;
    foreach my $key (keys %main::CONTAINERS) {
        next if (! ($key =~ /^$what/));
        foreach my $item (@{$main::CONTAINERS{$key}}) {
            delete $main::ITEMS{$item->{id}};
        }
        delete $main::CONTAINERS{$key};
    }

}