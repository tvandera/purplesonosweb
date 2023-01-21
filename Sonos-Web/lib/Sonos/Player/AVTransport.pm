package Sonos::Player::AVTransport;

use base 'Sonos::Player::Service';

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;


# Global
sub transportState($self)       { return $self->prop("TransportState"); }
sub currentPlayMode($self)      { return $self->prop("CurrentPlayMode"); }
sub currentTrack($self)         { return $self->prop("CurrentTrack"); }
sub numberOfTracks($self)       { return $self->prop("NumberOfTracks"); }
sub currentTrackDuration($self) { return $self->prop("CurrentTrackDuration"); }

# inside CurrentTransport or AVTransportURIMetaData
sub metaDataProp($self, @path) {
    my @elements = ( "CurrentTrackMetaData", "AVTransportURIMetaData" );
    for my $el (@elements) {
        my $value = $self->prop($el, @path );
        return $value if defined $value;
    }

    return undef;
}

sub title($self)   { return $self->metaDataProp("dc:title"); }
sub creator($self) { return $self->metaDataProp("dc:creator"); }
sub album($self)   { return $self->metaDataProp("upnp:album"); }

sub class($self) {
    my $full_classname = $self->metaDataProp("upnp:class");
    my @parts = split ".", $full_classname;
    return $parts[-1];
}

sub isRadio($self) {
    return $self->class() eq "audioBroadcast";
}

# CurrentTrack

sub info($self) {
    my @fields = (
        "transportState",
        "currentPlayMode",
        "class",
        "title",
        "creator",
        "album",
    );

    INFO "Update ". $self->friendlyName();
    for (@fields) {
        my $value = $self->$_();
        INFO "  " . $_ . ": " . $value if defined $value;
    }
}

# forward processUpdate to Service base class
sub processUpdate {
    my $self = shift;
    $self->processStateUpdate(@_);
}

1;