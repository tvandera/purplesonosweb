package Sonos::HTTP::Builder;

use v5.36;
use strict;
use warnings;


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
    my($self, $system, $qf, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _system => $system,
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
    return $self->{_system};
}

sub players($self) {
    return $self->system()->players();
}

sub lastUpdate($self) {
    return $self->system()->lastUpdate();
}

sub player($self, $name_or_uuid = undef) {
    $name_or_uuid = $self->qf("zone") unless $name_or_uuid;
    return $self->system()->player($name_or_uuid) if $name_or_uuid;
    return; # undef
}

sub qf($self, $field = undef, $default = undef) {
    return $self->{_qf} unless $field;
    my $value = $self->{_qf}->{$field};
    return $value ? $value : $default;
}

sub log($self, @args) {
    $self->system()->log("template", @args);
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
        $mpath_arg .= uri_escape_utf8($item->id()) . "&";
        $mpath_arg .= "zone=" . $player->friendlyName() . "&" if $player;

        %data = (
            $prefix . "_id"          => uri_escape_utf8( $item->id() ),
            $prefix . "_name"        => encode_entities( $item->title() ),
            $prefix . "_desc"        => encode_entities( $item->description() ),
            $prefix . "_artist"      => encode_entities( $item->creator() ),
            $prefix . "_album"       => encode_entities( $item->album() ),
            $prefix . "_class"       => encode_entities( $item->class  ),
            $prefix . "_content"     => uri_escape_utf8( $item->content  ),
            $prefix . "_parent"      => uri_escape_utf8( $item->parentID ),
            $prefix . "_albumart"    => $item->albumArtURI,
            $prefix . "_issong"      => int( $item->isSong() ),
            $prefix . "_isradio"     => int( $item->isRadio() ),
            $prefix . "_isalbum"     => int( $item->isAlbum() ),
            $prefix . "_isfav"       => int( $item->isFav() ),
            $prefix . "_istop"       => int( $item->isTop() ),
            $prefix . "_iscontainer" => int( $item->isContainer() ),
            $prefix . "_track_num"   => int( $item->originalTrackNumber() ),
            $prefix . "_arg"         => $mpath_arg,
        );
    } else {
        %data = (
            $prefix . "_id"          => "",
            $prefix . "_name"        => "",
            $prefix . "_desc"        => "",
            $prefix . "_artist"      => "",
            $prefix . "_album"       => "",
            $prefix . "_class"       => "",
            $prefix . "_content"     => "",
            $prefix . "_parent"      => "",
            $prefix . "_albumart"    => "",
            $prefix . "_issong"      => 0,
            $prefix . "_isradio"     => 0,
            $prefix . "_isalbum"     => 0,
            $prefix . "_isfav"       => 0,
            $prefix . "_iscontainer" => 0,
            $prefix . "_track_num"   => -1,
            $prefix . "_arg"         => "",
        );
    }


    return %data;
}

sub build_none_data($self) {
    return {};
}

###############################################################################
sub build_zones_data($self) {
    my @players = $self->players();


    @players = sort {
        # sort by zoneGroup coordinator
        fc($a->zoneGroupTopology()->coordinator()->friendlyName())
            cmp
        fc($b->zoneGroupTopology()->coordinator()->friendlyName())
        ||
        # then put coordinator first
            ($b->zoneGroupTopology()->isCoordinator())
        ||
        # then sort by zonename
            fc($a->friendlyName()) cmp fc($b->friendlyName())
    }  @players;
    my @zones = map { $self->build_zone_data( $_ ) } @players;
    return { "zones_loop" => \@zones };
}


###############################################################################
sub build_zone_data($self, $player = undef) {
    $player = $self->player() unless $player;
    return {} unless $player;

    my %activedata;
    my $updatenum = $self->qf("updatenum", -1);
    my $active_player = $self->player();

    my $render = $player->renderingControl();
    my $av = $player->avTransport();
    my $zonename = $player->zoneName();

    my $number_of_tracks = $av->numberOfTracks();
    my $transportstate = $av->transportState();
    my %transport_states = ( "TRANSITIONING" => 3, "PAUSED_PLAYBACK" => 2, "PLAYING" => 1, "STOPPED" => 0);
    my $nexttrack = $av->nextTrack();

    my $zonetopology  = $player->zoneGroupTopology();
    my $num_linked = $zonetopology->numMembers() - 1;

    $activedata{has_active_zone}   = int( defined $active_player );
    $activedata{active_zone}       = encode_entities( $zonename );
    $activedata{active_zoneid}     = uri_escape($player->UDN());
    $activedata{zone_active}       = int(defined $active_player && $player == $active_player );
    $activedata{active_lastupdate} = $player->lastUpdate();
    $activedata{active_updated}    = int( $player->lastUpdate() > $updatenum );

    $activedata{active_volume}   = $render->getVolume();
    $activedata{active_muted}    = $render->getMute();

    %activedata = ( %activedata, $self->build_item_data("active", $av->metaData(), $player) );
    $activedata{active_name} = $av->name();

    $activedata{active_length}    = $av->lengthInSeconds();
    $activedata{active_track_num} = int($av->currentTrack());
    $activedata{active_track_tot} = int($number_of_tracks);

    $activedata{"active_state"} = $transportstate;
    $activedata{"active_mode"} = $transport_states{$transportstate};
    $activedata{"active_$_"}   = int($transportstate eq $_) for (keys %transport_states);

    $activedata{active_repeat} = $av->isRepeat();
    $activedata{active_shuffle} = $av->isShuffle();

    %activedata = ( %activedata, $self->build_item_data("next", $nexttrack, $player) );

    $activedata{zone_mode}   = $activedata{active_mode};
    $activedata{zone_muted}  = $activedata{active_muted};
    $activedata{zone_id}     = $activedata{active_zoneid};
    $activedata{zone_name}   = $activedata{active_zone};
    $activedata{zone_volume} = $activedata{active_volume};
    $activedata{zone_arg}    = "zone=$zonename&";

    $activedata{zone_icon} = $zonetopology->icon();
    $activedata{zone_img} =  "zone_icons" . $zonetopology->icon() . ".png";
    $activedata{zone_lastupdate} = $player->lastUpdate();
    $activedata{zone_numlinked} = $num_linked;
    $activedata{zone_fancyname} = $activedata{zone_name};
    $activedata{zone_fancyname} .= " + " . $num_linked if $num_linked;

    my @members = $zonetopology->members();
    $activedata{ZONE_MEMBERS} = [
        map {
            my $uuid = $_->{UUID};
            {
                "zone_name"   => $zonetopology->zoneName($uuid),
                "zone_id"     => $uuid,
                "zone_linked" => int( ! $zonetopology->isCoordinator($uuid) ),
                "zone_icon"   => $zonetopology->icon($uuid),
                "zone_img"    => "zone_icons" . $zonetopology->icon($uuid) . ".png",
            }
        } @members
    ];

    $activedata{zone_linked}    = ! $zonetopology->isCoordinator();
    $activedata{zone_link}      = $zonetopology->coordinator()->UDN();
    $activedata{zone_link_name} = $zonetopology->coordinator()->friendlyName();

    return \%activedata;
}

###############################################################################
sub build_queue_data($self) {
    my $player = $self->player();
    return {} unless $player;

    my $queue = $player->queue();

    my %queuedata;

    $queuedata{queue_zone}       = $player->zoneName;
    $queuedata{queue_zoneid}     = uri_escape_utf8($player->UDN);

    my $updatenum = $self->qf("updatenum", -1);
    $queuedata{queue_lastupdate} = $queue->lastUpdate();
    $queuedata{queue_updated}    = int( $queue->lastUpdate() > $updatenum );

    my @loop_data = map { { $self->build_item_data("queue", $_, $player) } } $queue->items();
    $queuedata{queue_loop} = \@loop_data;

    return \%queuedata;
}

sub build_music_data($self) {
    my $updatenum = $self->qf("updatenum", -1);
    my %musicdata;

    my $mpath = $self->qf("mpath", "");
    $mpath    = "" if ( $mpath eq "/" );


    my $music      = $self->system()->musicLibrary();
    my $parent     = $music->item($mpath);

    my @elements;
    if (my $msearch = $self->qf("msearch")) {
        @elements   = $music->search($msearch);
    } else {
        @elements   = $music->children($parent);
    }

    $musicdata{"music_root"}       = int( $mpath eq "" );
    $musicdata{"music_lastupdate"} = $music->lastUpdate();
    $musicdata{"music_updated"}    = int( $music->lastUpdate() > $updatenum );
    $musicdata{"music_path"}       = encode_entities($mpath);

    %musicdata = (%musicdata, $self->build_item_data("music", $parent));

    my @music_loop_data = map { { $self->build_item_data("music", $_) } } @elements;

    $musicdata{"music_loop"} = \@music_loop_data;

    return \%musicdata;
}

sub build_globals_data($self) {
    my $updatenum = $self->qf("updatenum", -1);

    my $globals = {};
    $globals->{"version"}              = $self->version();
    $globals->{"last_update"}          = $self->lastUpdate();
    $globals->{"last_update_readable"} = localtime $self->lastUpdate();

    my $qf = $self->qf();
    my @keys    = grep !/action|rand|mpath|msearch|link/, ( keys %$qf );
    my $all_arg = join "&", map { "$_=$qf->{$_}" } @keys;
    $all_arg .= "&" if $all_arg;
    $globals->{"all_arg"} = $all_arg;

    $globals->{"musicdir_available"} = 0;
    $globals->{"zones_lastupdate"}   = $self->lastUpdate(); # FIXME
    $globals->{"zones_updated"}      = int( $self->lastUpdate() > $updatenum );

    return $globals;
}

###############################################################################
sub build_all_data($self) {
    my @categories = ( "globals" , "zone", "queue", "music", "zones" ) ;
    my @methods = map { "build_" . $_ . "_data" } @categories;
    my %data =  map { %{ $self->$_() } } @methods;
    return \%data;
}