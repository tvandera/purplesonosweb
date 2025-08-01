package Sonos::MetaData;

use v5.36;
use strict;
use warnings;
use Carp qw( carp );

use URI::Escape qw( uri_escape_utf8 );

use Types::Serialiser ();
use List::MoreUtils   qw( zip );

use constant NO_PARENT_ID => "NO_PARENT";
use constant ROOT_ID      => "";

sub topItems() {
    my @table = (
        [ "update_id", "dc:title",      "parentID",   "id", "upnp:class",    "icon" ],
        [ "",          "Music Library", NO_PARENT_ID, "",   "container.top", "library" ],

        [ "FavoritesUpdateID", "Favorites", "", "FV:2", "container.top", "favorite" ],

        [ "ShareListUpdateID", "Artists", "", "A:ARTIST", "container.top", "artist" ],
        [
            "ShareListUpdateID", "Albums", "", "A:ALBUM",
            "container.top",     "album"
        ],
        [
            "ShareListUpdateID", "Genres", "", "A:GENRE",
            "container.top",     "genre"
        ],
        [
            "ShareListUpdateID", "Composers",
            "",                  "A:COMPOSER",
            "container.top",     "composer"
        ],
        [
            "ShareListUpdateID", "Tracks", "", "A:TRACKS",
            "container.top",     "track"
        ],
        [
            "ShareListUpdateID", "Imported Playlists",
            "",                  "A:PLAYLISTS",
            "container.top",     "playlist"
        ],
        [ "ShareListUpdateID", "Folders", "", "S:", "container.top", "folder" ],

        [ "RadioLocationUpdateID", "Radio", "", "R:0/0", "container.top", "radio" ],

        [ "SavedQueuesUpdateID", "Playlists", "", "SQ:", "container.top", "sonos_playlist" ],
    );

    my @keys = @{ shift @table };
    return map {
        { zip( @keys, @$_ ) }
    } @table;
}

sub new {
    my ( $self, $data, $owner ) = @_;
    my $class = ref($self) || $self;

    if ($data) {

        # delete id or parentID if == -1
        for ( 'id', 'parentID' ) {
            next unless exists $data->{$_};
            next unless $data->{$_} eq "-1";
            delete $data->{$_};
        }
    }

    $self = bless {
        _owner => $owner,
        _data  => $data,
    }, $class;

    return $self;
}

# Sonos::Queue for Q: items
# Sonos::MusicLibrary for other
sub owner($self) {
    my $owner = $self->{_owner};

    if ( $self->id() =~ /^Q:/ ) {
        die "Incorrect owner $owner for Q:"
          unless $owner->isa("Sonos::Player::Queue");
    }
    else {
        die "Incorrect owner, expected MusicLibrary"
          unless $owner->isa("Sonos::MusicLibrary");
    }

    return $owner;
}

sub player($self) {
    return unless $self->id();

    # Queue item
    return $self->owner()->player() if $self->isQueueItem();

    # MusicLibrary item
    return $self->owner()->playerForID( $self->id() );
}

sub system($self) {
    return unless $self->id();
    return $self->player()->system();
}

sub musicLibrary($self) {
    return unless $self->id();
    return $self->system()->musicLibrary();
}

sub parent($self) {
    my $empty = Sonos::MetaData->new();

    return $empty if $self->isQueueItem();
    return $empty if $self->isRoot();

    return $self->musicLibrary()->item( $self->parentID() );
}

# true unless data is empty
sub populated($self) {
    return $self->{_data};
}

# TYPE=SNG|TITLE Why does it always rain on me?|ARTIST TRAVIS|ALBUM
sub streamContentProp( $self, $prop = undef ) {
    my $value = $self->prop("r:streamContent");
    return $value unless $value;

    my ( $type, $title, $artist, $album );
    if ( $value =~ /TYPE=(\w+)\|TITLE (.*)\|ARTIST (.*)\|ALBUM (.*)/ ) {
        ( $type, $title, $artist, $album ) = ( $1, $2, $3, $4 );
    }
    else {
        return $value;    # as is if no match
    }

    # return single field if requested
    my %mapping = ( "TITLE" => $title, "ARTIST" => $artist, "ALBUM" => $album );
    return $mapping{$prop} if $prop;

    # return non-empty fields, joined with a " - "
    my @fields = grep { $_ } ( $title, $artist, $album );
    return join " - ", @fields;
}

sub prop( $self, $path, $type = "string", $default = undef ) {
    my @path  = split "/", $path;
    my $value = $self->{_data};

    for (@path) {
        while ( ref $value eq 'ARRAY' and scalar @$value == 1 ) {
            $value = $value->[0];
        }
        $value = $value->{$_} if ( ref $value eq 'HASH' );
    }

    my %defaults = (
        "string" => "",
        "int"    => -1,
        "bool"   =>  0,
    );

    $default = $defaults{$type} unless defined $default;

    $value = $default unless defined $value;

    return $value         if $type eq "string";
    return int($value)    if $type eq "int";
    return $value ? 1 : 0 if $type eq "bool";

    carp "Unknown type: $type";
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

sub id($self)       { return $self->prop("id"); }
sub parentID($self) { return $self->prop("parentID"); }
sub content($self)  { return $self->prop("res/content"); }
sub title($self)    { return $self->prop("dc:title"); }
sub artist($self)   { return $self->prop("dc:creator"); }
sub album($self)    { return $self->prop("upnp:album"); }

sub arg($self) {
    my $mpath_arg = "";
    $mpath_arg .= $self->isQueueItem() ? "queue=" : "mpath=";
    $mpath_arg .= uri_escape_utf8( $self->id() ) . "&";
    $mpath_arg .= "zone=" . $self->player()->friendlyName() . "&"
      if $self->isQueueItem();
    return $mpath_arg;
}

sub TO_JSON($self) {
    return {} unless ( $self->populated() );
    return {
        "id"             => $self->id(),
        "arg"            => $self->arg(),
        "title"          => $self->title(),
        "desc"           => $self->description(),
        "artist"         => $self->artist(),
        "album"          => $self->album(),
        "class"          => $self->class(),
        "stream_content" => $self->streamContent(),
        "res_class"      => $self->resClass(),
        "content"        => $self->content(),
        "parent"         => $self->parentID(),
        "albumart"       => $self->albumArtURI(),
        "issong"         => Types::Serialiser::as_bool( $self->isSong() ),
        "isradio"        => Types::Serialiser::as_bool( $self->isRadio() ),
        "isalbum"        => Types::Serialiser::as_bool( $self->isAlbum() ),
        "isfav"          => Types::Serialiser::as_bool( $self->isFav() ),
        "istop"          => Types::Serialiser::as_bool( $self->isTop() ),
        "isroot"         => Types::Serialiser::as_bool( $self->isRoot() ),
        "iscontainer"    => Types::Serialiser::as_bool( $self->isContainer() ),
        "isplaylist"     => Types::Serialiser::as_bool( $self->isPlaylist() ),
        "track_num"      => int( $self->originalTrackNumber() ),
    };
}

sub albumArtURI($self) {
    my $icon = $self->prop("icon");
    return "icons/music/$icon" if $icon;

    my $aa = $self->prop("upnp:albumArtURI");

    # return first album art
    return $aa->[0] if ref $aa eq "ARRAY";

    # return any $aa
    return $aa if $aa;

    # content stream url
    return "/getaa?s=1&u=" . uri_escape_utf8( $self->content() )
      if $self->content();

    # nothingness
    return "";
}

sub originalTrackNumber($self) {
    return $self->prop( "upnp:originalTrackNumber", "int", -1 );
}
sub description($self) { return $self->prop("r:desciption"); }

sub streamContent($self)       { return $self->streamContentProp(); }
sub streamContentTitle($self)  { return $self->streamContentProp("TITLE"); }
sub streamContentArtist($self) { return $self->streamContentProp("ARTIST"); }
sub streamContentAlbum($self)  { return $self->streamContentProp("ALBUM"); }

sub radioShow($self) { return $self->prop("r:radioShowMd"); }

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
sub classFrom( $self, $from ) {
    my $full_classname = $self->prop($from);
    my @parts          = split( /\./, $full_classname );
    pop @parts if $parts[-1] && $parts[-1] =~ /#\w+/;
    return $parts[-1];
}

sub fullClass($self) {
    return $self->prop("upnp:class");
}

sub class($self) {
    return $self->classFrom("upnp:class");
}

# if this is a FV:0 item, the linked metadata will be in r:resMD
# r:resMD always seems to be an array of size 1
sub res($self) {
    my $resMD = $self->{_data}->{"r:resMD"}->[0];
    carp( "Missing r:resMD on Favorite: " . $self->id() )
      if $self->isFav()
      and !$resMD;
    return unless $resMD;
    carp( "Unexpected r:resMD on non-Favorite: " . $self->id() )
      if !$self->isFav();
    return Sonos::MetaData->new($resMD);
}

# if this is a FV:0 item
# it will have a "upnp:class": "object.itemobject.item.sonos-favorite",
# and the `real` class will be in
#  $item{"r:resMD"}->{"upnp:class"} "object.item.audioItem.audioBroadcast",
sub resClass($self) {
    return "" unless $self->isFav();
    return $self->res()->class();
}

# split using "/", take" the last part
# used for sorting and indexing Queue items
sub baseID($self) {
    my $full_id = $self->prop("id");
    return "" unless $full_id;
    my @parts = split( /\//, $full_id );
    return $parts[-1];
}

sub isRootItem($self) {
    return $self->parentID() eq NO_PARENT_ID;
}

sub isTopItem($self) {
    return $self->parentID() eq ROOT_ID;
}

sub isOfClass( $self, $class ) {
    return '1' if ( $self->class() eq $class );
    return '1' if ( $self->resClass() && $self->resClass() eq $class );
    return '0';
}

sub isRadio($self)    { return $self->isOfClass("audioBroadcast"); }
sub isSong($self)     { return $self->isOfClass("musicTrack"); }
sub isAlbum($self)    { return $self->isOfClass("musicAlbum"); }
sub isPlaylist($self) { return $self->isOfClass("playlistContainer"); }
sub isFav($self)      { return $self->class() eq "sonos-favorite"; }
sub isTop($self)      { return $self->isOfClass("top"); }

sub isRoot($self) {
    return $self->isTop() && ( $self->id() eq "/" || $self->id() eq "" );
}

sub isContainer($self) {
    my $fullclass = $self->prop("upnp:class");
    my $realclass = $self->prop("r:resMD/upnp:class");
    return $fullclass =~ m/container/g || $realclass =~ m/container/g;
}

sub isQueueItem($self) {
    return $self->id() =~ /^Q:/;
}

sub isPlayList($self) {
    return $self->class() eq "playlist";
}

sub getAlbumArt($self) {

    # ask owner for caching
    return $self->owner()->albumArtHelper($self);
}

sub didl($self) {
    my $id       = $self->id();
    my $parentid = $self->parentID();
    my $class    = $self->fullClass();
    my $title    = $self->title();

    my $metadata = <<"EOT";
<?xml version="1.0"?>
<DIDL-Lite
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
    xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"
    xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
  >
  <item id="$id" parentID="$parentid" restricted="true">
    <dc:title>
      $title
    </dc:title>
    <upnp:class>
      $class
    </upnp:class>
    <desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">
      RINCON_AssociatedZPUDN
    </desc>
  </item>
</DIDL-Lite>
EOT

    return $metadata;
}

sub displayFields() {
    return ( "id", "class", "title", "artist", "album", );
}

sub displayValues($self) {
    return map { $self->$_() } displayFields();
}

sub as_string($self) {
    return join " - ", $self->displayValues;
}

sub log( $self, $logger, $indent, @extraFields ) {
    return unless $self->populated();

    my @fields = ( displayFields(), @extraFields );
    for (@fields) {
        my $value = $self->$_();
        next unless defined $value and $value ne "";
        $logger->log( $indent . $_ . ": " . $value );
    }
}

1;
