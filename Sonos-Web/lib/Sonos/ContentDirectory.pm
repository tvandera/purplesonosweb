package Sonos::Container;

# Contains music library info
# caches for ContentDir

sub new {
    my($self, $device, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _device => $device,
        _containers => {},
        _items => {},
        _updateids => {}
    }, $class;

    return $self;
}

my ObjectIDs = (
    (  "Favorites", "FV:2", "tiles/favorites.svg");
    (  "Artists", "A:ARTIST", "tiles/artists.svg");
    (  "Albums", "A:ALBUM", "tiles/album.svg");
    (  "Genres", "A:GENRE", "tiles/genre.svg");
    (  "Composers", "A:COMPOSER", "tiles/composers.svg");
    (  "Tracks", "A:TRACKS", "tiles/track.svg");
    (  "Imported Playlists", "A:PLAYLISTS", "tiles/playlist.svg");
    (  "Folders", "S:", "tiles/folder.svg");
    (  "Radio", "R:0/0", "tiles/radio_logo.svg");
    (  "Line In", "AI:", "tiles/linein.svg");
    (  "Playlists", "SQ:", "tiles/sonos_playlists.svg");
)


# called when anything in ContentDirectory has been updated
# i.e.:
#  'SavedQueuesUpdateID' => 'RINCON_000E583472BC01400,12',
#  'ContainerUpdateIDs' => 'Q:0,503',
#  'RadioFavoritesUpdateID' => 'RINCON_000E583472BC01400,97',
#  'SystemUpdateID' => '131',
#  'FavoritePresetsUpdateID' => 'RINCON_000E583472BC01400,97',
#  'FavoritesUpdateID' => 'RINCON_000E583472BC01400,98',
#  'RadioLocationUpdateID' => 'RINCON_000E585187D201400,347',
#  'ShareListUpdateID' => 'RINCON_000E585187D201400,206'
sub processUpdate ( $self, $service, %properties ) {
    INFO Dumper \%properties;

    # check if anything was updated
    foreach my $key (keys %properties) {
        next if ($key !~ /UpdateID$/);
        my $oldvalue = $self->{_updateids}->{$key};
        my $newvalue = $properties{$key};
        my $updated = (not defined $oldvalue || $oldvalue ne $newvalue);
        my $updatemethod = $key =~ s/UpdateID/Updated/gr;

        # call e.g. $self->ContainerUpdated(%properties) if updated
        $self->$updatemethod(%properties) if $updated;
    }

    # merge new UpdateIDs into existing ones
    %{$self->{_updateids}} = ( %{$self->{_updateids}}, %properties);
}



###############################################################################
# objectid is like :
# - AI: for audio-in
# - Q:0 for queue
#
# actiontype is
#  - "BrowseMetadata", or
#  - "BrowseDirectChildren" (default)
sub fetchAndCache( $self, $objectid, $actiontype = 'BrowseDirectChildren') {
    my $start = 0;
    my @data  = ();
    my $result;

    do {
        $result = $self->contentDirProxy()->Browse( $objectid, $actiontype, 'dc:title,res,dc:creator,upnp:artist,upnp:album', $start, 2000, "" );

        carp("Browse ContentDirectory Failed") unless $result->isSuccessful;

        $start += $result->getValue("NumberReturned");

        my $results = $result->getValue("Result");
        my $tree    = XMLin(
            $results,
            forcearray => [ "item", "container" ],
            keyattr    => {}
        );

        push( @data, @{ $tree->{item} } ) if ( defined $tree->{item} );
        push( @data, @{ $tree->{container} } ) if ( defined $tree->{container} );
    } while ( $start < $result->getValue("TotalMatches") );

    return \@data;
}



###############################################################################
sub sonos_mkcontainer {
    my ($parent, $class, $title, $id, $icon, $content) = @_;

    my %data;

    $data{'upnp:class'}       = $class;
    $data{'dc:title'}         = $title;
    $data{'parentID'}         = $parent;
    $data{'id'}               = $id;
    $data{'upnp:albumArtURI'} = $icon;
    $data{'res'}->{content}   = $content if (defined $content);

    push (@{$main::CONTAINERS{$parent}},  \%data);

    $main::ITEMS{$data{'id'}} = \%data;
}

###############################################################################
sub sonos_mkitem {
    my ($parent, $class, $title, $id, $content) = @_;

    $main::ITEMS{$id}->{"upnp:class"}   = $class;
    $main::ITEMS{$id}->{'parentID'}       = $parent;
    $main::ITEMS{$id}->{"dc:title"}     = $title;
    $main::ITEMS{$id}->{'id'}             = $id;
    $main::ITEMS{$id}->{'res'}->{content} = $content if (defined $content);
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
sub get($self, $objectid, $item) {

}

###############################################################################
sub addRadioStation($self, $name, $station_url) {
    $station_url = substr( $station_url, 5 ) if ( substr( $station_url, 0, 5 ) eq "http:" );
    $name    = enc($name);

    my $item =
        '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" '
      . 'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
      . 'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
      . '<item id="" restricted="false"><dc:title>'
      . $name
      . '</dc:title><res>x-rincon-mp3radio:'
      . $station_url
      . '</res></item></DIDL-Lite>';

    return $self->createObject( "R:0/0", $item );
}

# add a radio station or play list
sub createObject( $self, $containerid, $elements ) {
    return  $self->contentDirProxy->CreateObject( $containerid, $elements );
}

# remove a radio station or play list
sub destroyObject( $self, $objectid ) {
    $self->contentDirProxy()->DestroyObject($objectid);
}

###############################################################################
sub refreshShareIndex($self) {
    $self->contentDirProxy()->RefreshShareIndex();
}