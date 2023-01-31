package Sonos::MetaDat;

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;



sub new {
    my($self, $data) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _data => $data,
        _players => {}, # UDN => Sonos::Player
        _contentcache => Sonos::ContentCache->new("global"),
        _loop => undef, # IO::Async::Loop::Select
    }, $class;

    $cp->searchByType( SERVICE_TYPE, sub { $self->_discoveryCallback(@_) });

    $self->addToLoop($loop) if defined $loop;

    return $self;
}

sub prop($self, @path) {
    my $value = $self->{_data};
    for (@path) {
        if (ref $value eq 'HASH' and defined $value->{$_}) {
            $value = $value->{$_};
        } else {
            return undef;
        }
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

# class
sub class($self) {
    my $full_classname = $self->metaDataProp("upnp:class");
    return undef unless defined $full_classname;

    # only the last part
    my @parts = split ".", $full_classname;
    return $parts[-1];
}

sub isRadio($self) {
    return $self->class() eq "audioBroadcast";
}

sub as_string($self, %) {
    #DEBUG Dumper($self->{_data});
    my @fields = (
        "class",
        "title",
        "creator",
        "album",
    );

    my @values = map { $self->$_() } @fields;
    return join " - ", @values;
}


1;