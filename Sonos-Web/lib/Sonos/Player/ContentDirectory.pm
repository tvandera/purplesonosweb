package Sonos::Player::ContentDirectory;

use v5.36;
use strict;
use warnings;

use base 'Sonos::Player::Service';

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

# Contains music library info
# caches for ContentDir

sub new {
    my($self, $device, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _containers => {},
        _items => {},
        _updateids => {}
    }, $class;

    return $self;
}

sub contentDirProxy($self) {
    return $self->{_device}->getService("ContentDirectory")->controlProxy;
}

my @ObjectIDs = (
    [ "FavoritesUpdateID", "Favorites",          "FV:2",        "tiles/favorites.svg" ],

    [ "ShareListUpdateID", "Artists",            "A:ARTIST",    "tiles/artists.svg" ],
    [ "ShareListUpdateID", "Albums",             "A:ALBUM",     "tiles/album.svg" ],
    [ "ShareListUpdateID", "Genres",             "A:GENRE",     "tiles/genre.svg" ],
    [ "ShareListUpdateID", "Composers",          "A:COMPOSER",  "tiles/composers.svg" ],
    [ "ShareListUpdateID", "Tracks",             "A:TRACKS",    "tiles/track.svg" ],
    [ "ShareListUpdateID", "Imported Playlists", "A:PLAYLISTS", "tiles/playlist.svg" ],
    [ "ShareListUpdateID", "Folders",            "S:",          "tiles/folder.svg" ],

    [ "RadioLocationUpdateID", "Radio", "R:0/0", "tiles/radio_logo.svg" ],

    [ "ContainerUpdateIDs", "Line In", "AI:", "tiles/linein.svg" ],
    [ "ContainerUpdateIDs", "Queue", "Q:0", "tiles/queue.svg" ],

    [ "SavedQueuesUpdateID", "Playlists", "SQ:", "tiles/sonos_playlists.svg" ],
);


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
    # check if anything was updated
    foreach my $key (keys %properties) {
        next if ($key !~ /UpdateIDs?$/);

        my $oldvalue = $self->{_updateids}->{$key} || "";
        my $newvalue = $properties{$key};

        # call fetchAndCache if updated
        $self->fetchAndCacheByUpdateID($key) if $oldvalue ne $newvalue;
    }

    # merge new UpdateIDs into existing ones
    %{$self->{_updateids}} = ( %{$self->{_updateids}}, %properties);
}


sub fetchAndCacheByUpdateID {
    my ($self, $updateid)  = @_;
    my @matching = grep { $_->[0] eq $updateid } @ObjectIDs;
    map { $self->fetchAndCacheByObjectId($_->[2]) } @matching;
}


###############################################################################
# objectid is like :
# - AI: for audio-in
# - Q:0 for queue
#
# actiontype is
#  - "BrowseMetadata", or
#  - "BrowseDirectChildren" (default)
sub fetchAndCacheByObjectId( $self, $objectid, $actiontype = 'BrowseDirectChildren') {
    my $start = 0;
    my @data  = ();
    my $result;

    INFO "Fetching " . $objectid;

    do {
        $result = $self->contentDirProxy()->Browse( $objectid, $actiontype, 'dc:title,res,dc:creator,upnp:artist,upnp:album', $start, 2000, "" );

        return undef unless $result->isSuccessful;

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

    INFO " .  Found " . scalar(@data) . " entries.";

    foreach my $item (@data) {
        $self->{_items}->{$item->{id}} = $item;
    }

    return \@data;
}

sub get($self, $id) {
    return $self->{_items}->{$id};
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
    return if $self->{_updateids}->{ShareIndexInProgress};
    $self->contentDirProxy()->RefreshShareIndex();
}

1;