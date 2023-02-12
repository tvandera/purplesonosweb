package Sonos::MetaData;

use v5.36;
use strict;
use warnings;

use List::MoreUtils qw(zip);

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;


sub rootItems() {
    my @table = (
        [ "update_id",             "dc:title",          "parentID", "id",   "upnp:class", "upnp:albumArtURI"  ],
        [ "",                      "Music Library",      "NO_PARENT", "",   "container", "tiles/library.svg" ],

        [ "FavoritesUpdateID",     "Favorites",          "", "FV:2",        "container.sonos-favorite", "tiles/favorites.svg" ],

        [ "ShareListUpdateID",     "Artists",            "", "A:ARTIST",    "container.musicArtist", "tiles/artists.svg" ],
        [ "ShareListUpdateID",     "Albums",             "", "A:ALBUM",     "container.musicAlbum", "tiles/album.svg" ],
        [ "ShareListUpdateID",     "Genres",             "", "A:GENRE",     "container.musicGenre", "tiles/genre.svg" ],
        [ "ShareListUpdateID",     "Composers",          "", "A:COMPOSER",  "container.composer", "tiles/composers.svg" ],
        [ "ShareListUpdateID",     "Tracks",             "", "A:TRACKS",    "container.musicTrack", "tiles/track.svg" ],
        [ "ShareListUpdateID",     "Imported Playlists", "", "A:PLAYLISTS", "container.playlistContainer", "tiles/playlist.svg" ],
        [ "ShareListUpdateID",     "Folders",            "", "S:",          "container.musicTrack", "tiles/folder.svg" ],

        [ "RadioLocationUpdateID", "Radio",              "", "R:0/0",       "container.audioBroadcast", "tiles/radio_logo.svg" ],

        [ "ContainerUpdateIDs",    "Line In",            "", "AI:",         "container", "tiles/linein.svg" ],
        [ "ContainerUpdateIDs",    "Queue",              "", "Q:0",         "container.musicTrack", "tiles/queue.svg" ],

        [ "SavedQueuesUpdateID",   "Playlists",          "", "SQ:",         "container.playlistContainer", "tiles/sonos_playlists.svg" ],
    );

    my @keys = @{shift @table};
    return map { { zip(@keys, @$_) } } @table;
}

sub new {
    my($self, $data, $musiclib) = @_;
	my $class = ref($self) || $self;

    if ($data) {
        for ('id', 'parentID') {
            next unless exists $data->{$_};
            next unless $data->{$_} eq "-1";
            delete $data->{$_};
        }
    }

    $self = bless {
        _musiclib => $musiclib,
        _data => $data,
    }, $class;

    return $self;
}

sub musicLibrary($self) {
    return $self->{_musiclib};
}

sub populated($self) {
    return $self->{_data};
}


# TYPE=SNG|TITLE Why does it always rain on me?|ARTIST TRAVIS|ALBUM
sub streamContentProp($self, $prop = undef) {
    my $value = $self->prop("r:streamContent");
    return $value unless $value;

    my ($type, $title, $artist, $album);
    if ($value =~ /TYPE=(\w+)\|TITLE (.*)\|ARTIST (.*)\|ALBUM (.*)/) {
        ($type, $title, $artist, $album) = ($1, $2, $3, $4);
    } else {
        return $value; # as is if no match
    }

    # return single field if requested
    my %mapping = ( "TITLE" => $title, "ARTIST" => $artist, "ALBUM" => $album );
    return $mapping{$prop} if $prop;

    # return non-empty fields, joined with a " - "
    my @fields = grep { $_ } ( $title, $artist, $album );
    return join " - ", @fields;
}

sub prop($self, @path) {
    my $value = $self->{_data};
    for (@path) {
        $value = $value->{$_} if (ref $value eq 'HASH');
    }

    return $value;
}


# "Q:0/15" : {
#    "dc:creator" : "Het Geluidshuis",
#    "dc:title" : "Radetski's (Lied)",
#    "id" : "Q:0/15",
#    "parentID" : "Q:0",
#    "res" : {
#       "content" : "x-file-cifs://pi/Music/kinderen/Het%20Geluidshuis/Dracula/deel%202/07%20Radetski's%20(Lied).mp3",
#       "protocolInfo" : "x-file-cifs:*:audio/mpeg:*"
#    },
#    "restricted" : "true",
#    "upnp:album" : "Dracula",
#    "upnp:albumArtURI" : "/getaa?u=x-file-cifs%3a%2f%2fpi%2fMusic%2fkinderen%2fHet%2520Geluidshuis%2fDracula%2fdeel%25202%2f07%2520Radetski's%2520(Lied).mp3&v=206",
#    "upnp:class" : "object.item.audioItem.musicTrack",
#    "upnp:originalTrackNumber" : "7"
# },

sub id($self)                  { return $self->prop("id"); }
sub parentID($self)            { return $self->prop("parentID"); }
sub content($self)             { return $self->prop("res", "content"); }
sub title($self)               { return $self->prop("dc:title"); }
sub creator($self)             { return $self->prop("dc:creator"); }
sub album($self)               { return $self->prop("upnp:album"); }
sub albumArtURI($self)         { return $self->prop("upnp:albumArtURI"); }
sub originalTrackNumber($self) { return $self->prop("upnp:originalTrackNumber"); }
sub description($self)         { return $self->prop("r:desciption"); }

sub streamContent($self)       { return $self->streamContentProp(); }
sub streamContentTitle($self)  { return $self->streamContentProp("TITLE"); }
sub streamContentArtist($self) { return $self->streamContentProp("ARTIST"); }
sub streamContentAlbum($self)  { return $self->streamContentProp("ALBUM"); }

sub radioShow($self)           { return $self->prop("r:radioShowMd"); }

#   if ( !ref( $curtrack->{item}->{"r:streamContent"} ) ) {
#       $activedata{ACTIVE_NAME} = enc( $curtrack->{item}->{"r:streamContent"} );
#   }

#   if ( !defined( $curtrack->{item}->{"dc:creator"} ) ) {
#       $activedata{ACTIVE_ALBUM} = enc( $curtransport->{item}->{"dc:title"} );
#   }

# class
# - "object.item"/>
# - "object.item.imageItem"/>
# - "object.item.imageItem.photo"/>
# - "object.item.audioItem"/>
# - "object.item.audioItem.musicTrack"/>
# - "object.item.audioItem.audioBroadcast"/>
# - "object.item.audioItem.audioBook"/>
# - "object.item.videoItem"/>
# - "object.item.videoItem.movie"/>
# - "object.item.videoItem.videoBroadcast"/>
# - "object.item.videoItem.musicVideoClip"/>
# - "object.item.playlistItem"/>
# - "object.item.textItem"/>
# - "object.item.bookmarkItem"/>
# - "object.item.epgItem"/>
# - "object.item.epgItem.audioProgram"/>
# - "object.item.epgItem.videoProgram"/>
# - "object.container.person"/>
# - "object.container.person.musicArtist"/>
# - "object.container.playlistContainer"/>
# - "object.container.album"/>
# - "object.container.album.musicAlbum"/>
# - "object.container.album.photoAlbum"/>
# - "object.container.genre"/>
# - "object.container.genre.musicGenre"/>
# - "object.container.genre.movieGenre"/>
# - "object.container.channelGroup"/>
# - "object.container.channelGroup.audioChannelGroup"/>
# - "object.container.channelGroup.videoChannelGroup"/>
# - "object.container.epgContainer"/>
# - "object.container.storageSystem"/>
# - "object.container.storageVolume"/>
# - "object.container.storageFolder"/>
# - "object.container.bookmarkFolder"/>
# only the last part
sub classFrom($self, @from) {
    my $full_classname = $self->prop(@from);
    my @parts = split( /\./, $full_classname);
    return $parts[-1];
}

sub class($self) {
    return $self->classFrom("upnp:class");
}

# if this is a FV:0 item
# it will have a "upnp:class": "object.itemobject.item.sonos-favorite",
# and the `real` class will be in
#  "r:resMD": {
#    "upnp:class": "object.item.audioItem.audioBroadcast",
sub realClass($self) {
    return $self->classFrom("r:resMD", "upnp:class");
}

# split using "/", take" the last part
sub baseID($self) {
    my $full_id = $self->prop("id");
    return undef unless $full_id;
    my @parts = split( /\//, $full_id);
    return $parts[-1];
}

sub isRadio($self) { return $self->class() eq "audioBroadcast"; }
sub isSong($self)  { return $self->class() eq "musicTrack"; }
sub isAlbum($self) { return $self->class() eq "musicAlbum"; }
sub isFav($self)   { return $self->class() eq "favorite"; }
sub isContainer($self) {
    my $class = $self->prop("upnp:class");
    return $class =~ m/container/g;
}


sub getAlbumArt($self, $baseurl) {
    return $self->musicLibrary()->albumArtHelper($self->albumArtURI, $baseurl);
}

sub displayFields() {
    return  (
        "id",
        "class",
        "title",
        "creator",
        "album",
        "streamContent",
    );
}

sub displayValues($self) {
    return map { $self->$_() } displayFields();
}

sub as_string($self) {
    return join " - ", $self->diplayValues;
}

sub log($self, $logger, $indent) {
    return unless $self->populated();

    for (displayFields()) {
        my $value = $self->$_();
        next unless defined $value and $value ne "";
        $logger->log($indent . $_ . ": " . $value);
    }
}

1;