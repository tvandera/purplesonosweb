package Sonos::HTTP::NestedBuilder;

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

    $self->{"_json"}->pretty(1)->canonical(1);

    return $self;
}

sub version($self) {
    return "0.99";
}

sub system($self) {
    return $self->{"_system"};
}

sub players($self, $sorted = 1) {
    my @players = $self->system()->players();

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
    }  @players unless !$sorted;

    return @players;
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
    return $self->{"_qf"} unless $field;
    my $value = $self->{"_qf"}->{$field};
    return $value ? $value : $default;
}

sub log($self, @args) {
    $self->system()->log("template", @args);
}

sub to_json {
    my $self = shift;
    $self->{"_json"}->encode(@_);
}


sub build_item_data($self, $item, $player = undef) {
    my %data;
    if ($item->populated()) {
        my $mpath_arg = "";
        $mpath_arg .= $item->isQueueItem() ?  "queue=" : "mpath=";
        $mpath_arg .= uri_escape_utf8($item->id()) . "&";
        $mpath_arg .= "zone=" . $player->friendlyName() . "&" if $player;

        %data = (
            "id"          => $item->id(),
            "name"        => encode_entities( $item->title() ),
            "desc"        => encode_entities( $item->description() ),
            "artist"      => encode_entities( $item->creator() ),
            "album"       => encode_entities( $item->album() ),
            "class"       => encode_entities( $item->class  ),
            "real_class"  => encode_entities( $item->realClass()  ),
            "content"     => $item->content,
            "parent"      => $item->parentID,
            "albumart"    => $item->albumArtURI,
            "issong"      => int( $item->isSong() ),
            "isradio"     => int( $item->isRadio() ),
            "isalbum"     => int( $item->isAlbum() ),
            "isfav"       => int( $item->isFav() ),
            "istop"       => int( $item->isTop() ),
            "iscontainer" => int( $item->isContainer() ),
            "isplaylist"  => int( $item->isPlaylist() ),
            "track_num"   => int( $item->originalTrackNumber() ),
            "arg"         => $mpath_arg,
        );
    } else {
        %data = (
            "id"          => "",
            "id_uri"      => "",
            "name"        => "",
            "desc"        => "",
            "artist"      => "",
            "album"       => "",
            "class"       => "",
            "content"     => "",
            "parent"      => "",
            "albumart"    => "",
            "issong"      => 0,
            "isradio"     => 0,
            "isalbum"     => 0,
            "isfav"       => 0,
            "iscontainer" => 0,
            "track_num"   => -1,
            "arg"         => "",
        );
    }


    return \%data;
}

sub build_none_data($self) {
    return {};
}

###############################################################################
sub build_zones_data($self) {
    my @zones = map { $self->build_zone_data( $_ ) } $self->players();
    return { "zones" => \@zones };
}


###############################################################################
sub build_zone_data($self, $player = undef) {
    $player = $self->player() unless $player;
    return {} unless $player;

    my $updatenum = $self->qf("updatenum", -1);
    my $active_player = $self->player();

    my $render = $player->renderingControl();
    my $av = $player->avTransport();
    my $zonename = $player->zoneName();

    my $number_of_tracks = $av->numberOfTracks();
    my $transportstate = $av->transportState();
    my %transport_states = ( "TRANSITIONING" => 3, "PAUSED_PLAYBACK" => 2, "PLAYING" => 1, "STOPPED" => 0);
    my %state_toggles = map { "is_" . $_ => int($transportstate eq $_) } keys %transport_states;
    my $nexttrack = $av->nextTrack();

    my $zonetopology  = $player->zoneGroupTopology();
    my $num_linked = $zonetopology->numMembers() - 1;
    my $fancyname =  $zonename;
    $fancyname .= " + " . $num_linked if $num_linked;

    return {
        "has_active_zone"   => int( defined $active_player ),

        "zonename"   => encode_entities( $zonename ),
        "zoneid"     => uri_escape($player->UDN()),
        "lastupdate" => $player->lastUpdate(),
        "updated"    => int( $player->lastUpdate() > $updatenum ),

        "volume"     => $render->getVolume(),
        "muted"      => $render->getMute(),

        "current_track" => $self->build_item_data($av->metaData(), $player),
        "title"         => $av->name(),
        "zone_arg"           => "zone=$zonename&",

        "length"    => $av->lengthInSeconds(),
        "track_num" => int($av->currentTrack()),
        "track_tot" => int($number_of_tracks),

        "state"     => $transportstate,
        "mode"     => $transport_states{$transportstate},

        "repeat"  => $av->isRepeat(),
        "shuffle" => $av->isShuffle(),

        "next" => $self->build_item_data($nexttrack, $player),

        "icon" => $zonetopology->icon(),
        "img" =>  "icons" . $zonetopology->icon() . ".png",
        "lastupdate" => $player->lastUpdate(),
        "numlinked" => $num_linked,
        "fancyname" => $fancyname,

        "linked"    => ! $zonetopology->isCoordinator(),
        "link"      => $zonetopology->coordinator()->UDN(),
        "link_name" => $zonetopology->coordinator()->friendlyName(),

        "members" => [
            map {
                my $uuid = $_->{"UUID"};
                {
                    "name"   => $zonetopology->zoneName($uuid),
                    "id"     => $uuid,
                    "linked" => int( ! $zonetopology->isCoordinator($uuid) ),
                    "icon"   => $zonetopology->icon($uuid),
                    "img"    => "icons" . $zonetopology->icon($uuid) . ".png",
                }
            } $zonetopology->members()
        ]
    };
}

sub build_info_data {
    return build_zone_data @_;
}

###############################################################################
sub build_queue_data($self) {
    my $player = $self->player();
    return {} unless $player;

    my $queue = $player->queue();
    my $updatenum = $self->qf("updatenum", -1);

    return {
        "zone"       => $player->zoneName,
        "zoneid"     => uri_escape_utf8($player->UDN),
        "lastupdate" => $queue->lastUpdate(),
        "updated"    => int( $queue->lastUpdate() > $updatenum ),
        "queue"      => [ map { $self->build_item_data($_, $player) } $queue->items() ],
    };
}

sub build_music_data($self) {
    my $updatenum = $self->qf("updatenum", -1);

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

    return {
        "root"       => int( $mpath eq "" ),
        "lastupdate" => $music->lastUpdate(),
        "updated"    => int( $music->lastUpdate() > $updatenum ),
        "path"       => encode_entities($mpath),
        "item"       => $self->build_item_data($parent),
        "children"   => [ map { $self->build_item_data($_) } @elements ]
    }
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
    my @categories = ( "globals", "zone", "queue", "music", "zones" ) ;
    my %methods = map { $_ => "build_" . $_ . "_data" } @categories;
    my %data = ();
    while (my ($key, $value) = each(%methods)) {
        $data{$key} = $self->$value();
    }
    return \%data;
}