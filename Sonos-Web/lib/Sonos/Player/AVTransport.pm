package Sonos::Player::AVTransport;

use base 'Sonos::Player::Service', 'Sonos::MetaData';

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

# override prop to also look inside CurrentTrackMetaData or
# AVTransportURIMetaData
sub prop($self, @path) {
    my @elements = ( (), "AVTransportURIMetaData", "CurrentTrackMetaData");
    for (@elements) {
        my $value = $self->SUPER::prop($_, @path );
        return $value if defined $value;
    }

    return undef;
}


sub info($self) {
    #DEBUG Dumper($self->{_state});
    my @fields = (
        "transportState",
        "currentPlayMode",
        "class",
        "title",
        "creator",
        "album",
        "streamContent",
        "radioShow",
    );

    $self->log($self->shortName(), ":");
    for (@fields) {
        my $value = $self->$_();
        $self->log("  " . $_ . ": " . $value) if defined $value;
    }
}

1;