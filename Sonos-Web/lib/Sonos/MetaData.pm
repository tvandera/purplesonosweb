package Sonos::MetaData;

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;


sub new {
    my($self, $data, $cache) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _cache => $cache,
        _data => $data,
    }, $class;

    return $self;
}

sub cache($self) {
    return $self->{_cache};
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
sub class($self) {
    my $full_classname = $self->prop("upnp:class");
    # only the last part
    my @parts = split( /\./, $full_classname);
    return $parts[-1];
}

sub realclass($self) {
    # FIXME
    return $self->class;
}

sub baseID($self) {
    my $full_id = $self->prop("id");
    # only the last part
    my @parts = split( /\//, $full_id);
    return $parts[-1];
}

sub isRadio($self) { return $self->class() eq "audioBroadcast"; }
sub isSong($self)  { return $self->class() eq "musicTrack"; }
sub isAlbum($self) { return $self->class() eq "musicAlbum"; }
sub isFav($self)   { return $self->class() eq "favorite"; }

sub getAlbumArt($self, $baseurl) {
    return $self->cache()->albumArtHelper($self->albumArtURI, $baseurl);
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
    for (displayFields()) {
        my $value = $self->$_();
        next unless defined $value and $value ne "";
        $logger->log($indent . $_ . ": " . $value);
    }
}

1;