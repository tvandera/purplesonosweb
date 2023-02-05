package Sonos::Player::AVTransport;

use base 'Sonos::Player::Service';

require Sonos::MetaData;

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

sub nextTrack($self) { return Sonos::MetaData->new($self->prop("r:NextTrackMetaData")); }
sub curTrack($self)  { return Sonos::MetaData->new($self->prop("CurrentTrackMetaData")); }
sub curTransport($self)  { return Sonos::MetaData->new($self->prop("AVTransportURIMetaData")); }

sub info($self) {
    #DEBUG Dumper($self->{_state});
    my @fields = (
        "transportState",
        "currentPlayMode",
    );

    $self->log($self->shortName(), ":");
    for (@fields) {
        my $value = $self->$_();
        $self->log("  " . $_ . ": " . $value) if defined $value;
    }
    $self->log("  Current Track:");
    $self->curTrack()->log($self, " " x 4);

    $self->log("  Current Transport:");
    $self->curTransport()->log($self, " " x 4);

    $self->log("  Next Track:");
    $self->curTransport()->log($self, " " x 4);
}

1;