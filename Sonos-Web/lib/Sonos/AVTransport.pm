package Sonos::AVTransport;

use base 'Sonos::Service';

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;


sub prop($self, @path) {
    my $value = $self->{_state};
    map { $value = $value->{$_}; } (@path);
    return $value;
}

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

    INFO "AVTransport: ". Dumper($self->{_state});
    for (@fields) {
        my $value = $self->$_();
        INFO "  " . $_ . ": " . $value if defined $value;
    }
}

    #         $activedata{ACTIVE_NAME} = enc( $curtrack->{item}->{"dc:title"} );
    #         $activedata{ACTIVE_ARTIST} =
    #           enc( $curtrack->{item}->{"dc:creator"} );
    #         $activedata{ACTIVE_ALBUM} =
    #           enc( $curtrack->{item}->{"upnp:album"} );
    #         $activedata{ACTIVE_TRACK_NUM} =
    #           $state->{CurrentTrack};
    #         $activedata{ACTIVE_TRACK_TOT} =
    #           $state->{NumberOfTracks};
    #         $activedata{ACTIVE_TRACK_TOT_0} =
    #           ( $state->{NumberOfTracks} == 0 );
    #         $activedata{ACTIVE_TRACK_TOT_1} =
    #           ( $state->{NumberOfTracks} == 1 );
    #         $activedata{ACTIVE_TRACK_TOT_GT_1} =
    #           ( $state->{NumberOfTracks} > 1 );
    #     }

    # if ( $state->{CurrentTrackDuration} ) {
    #     my @parts =
    #       split( ":", $state->{CurrentTrackDuration} );
    #     $activedata{ACTIVE_LENGTH} =
    #       $parts[0] * 3600 + $parts[1] * 60 + $parts[2];
    # }

    # my $nexttrack = $state->{"r:NextTrackMetaData"};
    # if ($nexttrack) {
    #     $activedata{NEXT_NAME}   = enc( $nexttrack->{item}->{"dc:title"} );
    #     $activedata{NEXT_ARTIST} = enc( $nexttrack->{item}->{"dc:creator"} );
    #     $activedata{NEXT_ALBUM}  = enc( $nexttrack->{item}->{"upnp:album"} );
    #     $activedata{NEXT_ISSONG} = 1;
    # }

    # $activedata{ZONE_MODE}   = $activedata{ACTIVE_MODE};
    # $activedata{ZONE_MUTED}  = $activedata{ACTIVE_MUTED};
    # $activedata{ZONE_ID}     = $activedata{ACTIVE_ZONEID};
    # $activedata{ZONE_NAME}   = $activedata{ACTIVE_ZONE};
    # $activedata{ZONE_VOLUME} = $activedata{ACTIVE_VOLUME};
    # $activedata{ZONE_ARG}    = "zone=" . uri_escape_utf8($zone) . "&";

# handled in base class
sub processUpdate {
    my $self = shift;
    $self->processStateUpdate(@_);
}

1;