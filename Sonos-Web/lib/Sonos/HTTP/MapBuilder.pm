package Sonos::HTTP::Builder;

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;
use Carp;

require IO::Async::Listener;
require HTTP::Daemon;
use HTTP::Status ":constants";
use HTML::Entities;
use URI::Escape;
use Encode qw(encode decode);
use URI::WithBase;
use File::Spec::Functions 'catfile';
require JSON;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use MIME::Types;

###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $discover, $qf, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _discovery => $discover,
        _qf => $qf,
        _json => JSON->new(),
    }, $class;

    $self->{_json}->pretty(1)->canonical(1);

    return $self;
}

sub version($self) {
    return "0.99";
}

sub system($self) {
    return $self->{_discovery};
}

sub players($self) {
    return $self->system()->players();
}

sub lastUpdate($self) {
    return $self->system()->lastUpdate();
}

sub player($self, $name_or_uuid) {
    return $self->system()->player($name_or_uuid);
}

sub baseURL($self) {
    return "/";
}

sub diskpath($self, $path) {
    return catfile("html", $path);
}

sub qf($self, $field = undef, $default = undef) {
    return $self->{_qf} unless $field;
    my $value = $self->{_qf}->{$field};
    return $value ? $value : $default;
}

sub log($self, @args) {
    INFO sprintf("[%12s]: ", "template"), @args;
}

sub to_json {
    my $self = shift;
    $self->{_json}->encode(@_);
}

sub build_item_data($self, $prefix, $item, $player = undef) {
    my %data;
    if ($item->populated()) {
        my $mpath_arg = "";
        $mpath_arg .= $item->isQueueItem() ?  "queue=" : "mpath=";
        $mpath_arg .= uri_escape_utf8($item->id());
        $mpath_arg .= "&zone=" . $player->friendlyName() . "&" if $player;

        %data = (
            $prefix . "_NAME"        => encode_entities( $item->title() ),
            $prefix . "_ARTIST"      => encode_entities( $item->creator() ),
            $prefix . "_ALBUM"       => encode_entities( $item->album() ),
            $prefix . "_CLASS"       => encode_entities( $item->class  ),
            $prefix . "_CONTENT"     => uri_escape_utf8( $item->content  ),
            $prefix . "_PARENT"      => uri_escape_utf8( $item->parentID ),
            $prefix . "_ALBUMART"    => $item->albumArtURI,
            $prefix . "_ISSONG"      => int( $item->isSong() ),
            $prefix . "_ISRADIO"     => int( $item->isRadio() ),
            $prefix . "_ISALBUM"     => int( $item->isAlbum() ),
            $prefix . "_ISFAV"       => int( $item->isFav() ),
            $prefix . "_ISCONTAINER" => int( $item->isContainer() ),
            $prefix . "_ARG"         => $mpath_arg,
        );
    } else {
        %data = (
            $prefix . "_NAME"        => "",
            $prefix . "_ARTIST"      => "",
            $prefix . "_ALBUM"       => "",
            $prefix . "_CLASS"       => "",
            $prefix . "_CONTENT"     => "",
            $prefix . "_PARENT"      => "",
            $prefix . "_ARG"         => "",
            $prefix . "_ISSONG"      => 0,
            $prefix . "_ISRADIO"     => 0,
            $prefix . "_ISALBUM"     => 0,
            $prefix . "_ISFAV"       => 0,
            $prefix . "_ISCONTAINER" => 0,
            $prefix . "_ARG"         => "",
        );
    }


    return %data;
}


###############################################################################
sub build_zones_data($self) {
    my @zones = map { $self->build_zone_data( $_ ) } $self->players();
    return \@zones;
}


###############################################################################
sub build_zone_data($self, $player = undef) {
    $player = $self->qf("player") unless $player;
    return {} unless $player;

    my %activedata;
    my $updatenum = $self->qf("updatenum", -1);
    my $active_player = $self->qf("zone");

    my $render = $player->renderingControl();
    my $av = $player->avTransport();
    my $zonename = $player->zoneName();
    my $number_of_tracks = $av->numberOfTracks();
    my $transportstate = $av->transportState();
    my %transport_states = ( "TRANSITIONING" => 3, "PAUSED_PLAYBACK" => 2, "PLAYING" => 1, "STOPPED" => 0);
    my $nexttrack = $av->nextTrack();

    my $zonetopology  = $player->zoneGroupTopology();
    my $num_linked = $zonetopology->numMembers() - 1;

    $activedata{HAS_ACTIVE_ZONE}   = int( defined $active_player );
    $activedata{ACTIVE_ZONE}       = encode_entities( $zonename );
    $activedata{ACTIVE_ZONEID}     = uri_escape($player->UDN());
    $activedata{ZONE_ACTIVE}       = int(defined $active_player && $player == $active_player );
    $activedata{ACTIVE_LASTUPDATE} = $player->lastUpdate();
    $activedata{ACTIVE_UPDATED}    = ( $player->lastUpdate() > $updatenum );

    $activedata{ACTIVE_VOLUME}   = $render->getVolume();
    $activedata{ACTIVE_MUTED}    = $render->getMute();

    %activedata = ( %activedata, $self->build_item_data("ACTIVE", $av, $player) );

    $activedata{ACTIVE_LENGTH}   = $av->lengthInSeconds();
    $activedata{ACTIVE_TRACK_NUM} = encode_entities($av->currentTrack());

    $activedata{ACTIVE_TRACK_TOT} = encode_entities($number_of_tracks);
    $activedata{ACTIVE_TRACK_TOT_0} = ( $number_of_tracks == 0 );
    $activedata{ACTIVE_TRACK_TOT_1} = ( $number_of_tracks == 1 );
    $activedata{ACTIVE_TRACK_TOT_GT_1} = ( $number_of_tracks > 1 );

    $activedata{"ACTIVE_MODE"} = $transport_states{$transportstate};
    $activedata{"ACTIVE_$_"}   = ($transportstate eq $_) for (keys %transport_states);

    $activedata{ACTIVE_REPEAT} = $av->isRepeat();
    $activedata{ACTIVE_SHUFFLE} = $av->isShuffle();

    %activedata = ( %activedata, $self->build_item_data("NEXT", $nexttrack, $player) );

    $activedata{ZONE_MODE}   = $activedata{ACTIVE_MODE};
    $activedata{ZONE_MUTED}  = $activedata{ACTIVE_MUTED};
    $activedata{ZONE_ID}     = $activedata{ACTIVE_ZONEID};
    $activedata{ZONE_NAME}   = $activedata{ACTIVE_ZONE};
    $activedata{ZONE_VOLUME} = $activedata{ACTIVE_VOLUME};
    $activedata{ZONE_ARG}    = "zone=$zonename&";

    $activedata{ZONE_ICON} = $zonetopology->icon();
    $activedata{ZONE_LASTUPDATE} = $player->lastUpdate();
    $activedata{ZONE_NUMLINKED} = $num_linked;
    $activedata{ZONE_FANCYNAME} = $activedata{ZONE_NAME};
    $activedata{ZONE_FANCYNAME} .= " + " . $num_linked if $num_linked;

    my @members = $zonetopology->members();
    $activedata{ZONE_MEMBERS} = [
        map {
            my $uuid = $_->{UUID};
            {
                "ZONE_NAME"   => $zonetopology->zoneName($uuid),
                "ZONE_ID"     => $uuid,
                "ZONE_LINKED" => int( ! $zonetopology->isCoordinator($uuid) ),
                "ZONE_ICON"   => $zonetopology->icon($uuid),
            }
        } @members
    ];

    $activedata{ZONE_LINKED}    = ! $zonetopology->isCoordinator();
    $activedata{ZONE_LINK}      = $zonetopology->coordinator()->{UUID};
    $activedata{ZONE_LINK_NAME} = $zonetopology->coordinator()->{ZoneName};

    $activedata{ACTIVE_JSON} = $self->to_json( \%activedata );

    return \%activedata;
}

###############################################################################
sub build_queue_data($self) {
    my $player = $self->qf("zone");
    return {} unless $player;

    my $queue = $player->queue();

    my %queuedata;

    $queuedata{QUEUE_ZONE}       = $player->zoneName;
    $queuedata{QUEUE_ZONEID}     = uri_escape_utf8($player->UDN);

    my $updatenum = $self->qf("updatenum", -1);
    $queuedata{QUEUE_LASTUPDATE} = $queue->lastUpdate();
    $queuedata{QUEUE_UPDATED}    = ( $queue->lastUpdate() > $updatenum );

    my @loop_data = map { { $self->build_item_data("QUEUE", $_, $player) } } $queue->items();
    $queuedata{QUEUE_LOOP} = \@loop_data;
    $queuedata{QUEUE_JSON} = $self->to_json( \@loop_data );

    return \%queuedata;
}

sub build_music_data($self) {
    my %musicdata;

    my $mpath = $self->qf("mpath", "");
    $mpath    = "" if ( $mpath eq "/" );

    $musicdata{"MUSIC_ROOT"}       = int( $mpath eq "" );
    $musicdata{"MUSIC_LASTUPDATE"} = $main::MUSICUPDATE;
    $musicdata{"MUSIC_PATH"}       = encode_entities($mpath);

    my $music      = $self->system()->musicLibrary();
    my $parent     = $music->item($mpath);
    my @elements   = $music->children($parent);

    %musicdata = (%musicdata, $self->build_item_data("MUSIC", $parent));
    $musicdata{"MUSIC_UPDATED"}    = 1;


    my @music_loop_data = map { { $self->build_item_data("MUSIC", $_) } } @elements;

    $musicdata{"MUSIC_LOOP"} = \@music_loop_data;

    return \%musicdata;
}

sub build_globals_data($self) {
    my $updatenum = $self->qf("updatenum", -1);

    my $globals = {};
    $globals->{"VERSION"}              = $self->version();
    $globals->{"LAST_UPDATE"}          = $self->lastUpdate();
    $globals->{"LAST_UPDATE_READABLE"} = localtime $self->lastUpdate();

    my $qf = $self->qf();
    my @keys    = grep !/action|rand|mpath|msearch|link/, ( keys %$qf );
    $globals->{"ALL_ARG"} = join "&", map { "$_=$qf->{$_}" } @keys;

    $globals->{"MUSICDIR_AVAILABLE"} = 0;
    $globals->{"ZONES_LASTUPDATE"}   = $self->lastUpdate(); # FIXME
    $globals->{"ZONES_UPDATED"}      = ( $self->lastUpdate() > $updatenum );

    return $globals;
}

###############################################################################
sub build_map($self) {
    my %map = ();

    my $globals = $self->build_globals_data();
    $map{GLOBALS_JSON} = $self->to_json( $globals );
    %map = ( %map, %$globals );

    my $zones = $self->build_zones_data();
    $map{ZONES_LOOP} = $zones;
    $map{ZONES_JSON} = $self->to_json( $zones );

    my $queue = $self->build_queue_data();
    $map{QUEUE_JSON} = $self->to_json( $queue );
    %map = ( %map, %$queue );

    my $music = $self->build_music_data();
    $map{MUSIC_JSON} = $self->to_json( $music );
    %map = ( %map, %$music );

    my $zone = $self->build_zone_data( $self->qf("player") );
    %map = ( %map, %$zone );

    return \%map;
}