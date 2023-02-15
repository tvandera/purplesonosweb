package Sonos::HTTP::Template;

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
use JSON;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use MIME::Types;

require HTML::Template;

###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $discover, $diskpath, $qf, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _discovery => $discover,
        _qf => $qf,
    }, $class;

    # One of our templates, now fill in the parts we know
    my $template = HTML::Template->new(
        filename          => $diskpath,
        die_on_bad_params => 0,
        global_vars       => 1,
        use_query         => 1,
        loop_context_vars => 1
    );

    my @params = $template->param();
    my $map    = $self->build_map( $qf, \@params );
    $template->param(%$map);
    $self->{_template} = $template;

    return $self;
}

sub template($self) {
    return $self->{_template};
}

sub output($self) {
    return $self->template()->output();
}

sub version($self) {
    return "0.99";
}

sub getSystem($self) {
    return $self->{_discovery};
}

sub players($self) {
    return $self->getSystem()->players();
}

sub lastUpdate($self) {
    return $self->getSystem()->lastUpdate();
}

sub zonePlayer($self, $name) {
    return $self->getSystem()->zonePlayer($name);
}

sub baseURL($self) {
    return "/";
}

sub defaultPage($self) {
    return $self->{_default_page};
}

sub mimeTypeOf($self, $p) {
    return $self->{_mime_types}->mimeTypeOf($p);
}

sub diskpath($self, $path) {
    return catfile("html", $path);
}

sub log($self, @args) {
    INFO sprintf("[%12s]: ", "template"), @args;
}

sub build_item_data($self, $prefix, $item, $player = undef) {
    my %data;
    if ($item->populated()) {
        my $zone_arg = "";
        my $mpath_arg = "";
        my $aa_arg = "";

        $player = $item->player() unless $player;

        $zone_arg = "&zone=" . $item->player()->zoneName() if ($item->player());
        $mpath_arg = "mpath=" . uri_escape_utf8($item->id()) . $zone_arg if $item->id();
        $aa_arg = "/getaa?" . $mpath_arg . $zone_arg if $mpath_arg;

        %data = (
            $prefix . "_NAME"        => encode_entities( $item->title() ),
            $prefix . "_ARTIST"      => encode_entities( $item->creator() ),
            $prefix . "_ALBUM"       => encode_entities( $item->album() ),
            $prefix . "_CLASS"       => encode_entities( $item->class  ),
            $prefix . "_CONTENT"     => uri_escape_utf8( $item->content  ),
            $prefix . "_PARENT"      => uri_escape_utf8( $item->parentID ),
            $prefix . "_IMG"         => $aa_arg,
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
sub build_zone_data($self, $player, $updatenum, $active_player ) {
    my %activedata;

    my $render = $player->renderingControl();
    my $av = $player->avTransport();
    my $zonename = $player->zoneName();
    my $item = $av->curMetaData();
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

    %activedata = ( %activedata, $self->build_item_data("ACTIVE", $item, $player) );

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

    $activedata{ZONE_MEMBERS} = [
        map {
            {
                "ZONE_NAME" => $_->{ZoneName},
                "ZONE_ID"   => $_->{UUID},
                "ZONE_LINKED" => -1, #int( ! $_->isCoordinator() ),
                "ZONE_ICON" => $_->{Icon},
            }
        } values %{$zonetopology->allZones()}
    ];

    $activedata{ZONE_LINKED}    = ! $zonetopology->isCoordinator();
    $activedata{ZONE_LINK}      = $zonetopology->coordinator()->{UUID};
    $activedata{ZONE_LINK_NAME} = $zonetopology->coordinator()->{ZoneName};

    $activedata{ACTIVE_JSON} = to_json( \%activedata, { pretty => 1 } );

    return \%activedata;
}

###############################################################################
sub build_queue_data {
    my ($self, $player, $updatenum ) = @_;
    my $contentdir = $player->contentDirectory();

    my %queuedata;

    $queuedata{QUEUE_ZONE}       = $player->zoneName;
    $queuedata{QUEUE_ZONEID}     = uri_escape_utf8($player->UDN);
    $queuedata{QUEUE_LASTUPDATE} = $contentdir->lastUpdate();
    $queuedata{QUEUE_UPDATED}    = ( $contentdir->lastUpdate() > $updatenum );

    my @loop_data = map { { $self->build_item_data("QUEUE", $_, $player) } } $contentdir->queueItems();
    $queuedata{QUEUE_LOOP} = \@loop_data;
    $queuedata{QUEUE_JSON} = to_json( \@loop_data, { pretty => 1 } );

    return \%queuedata;
}

sub build_music_data {
    my $self      = shift;
    my $qf        = shift;
    my $updatenum = shift;
    my %musicdata;

    my $mpath = "";
    $mpath = $qf->{mpath} if ( defined $qf->{mpath} );
    $mpath = ""           if ( $mpath eq "/" );
    my $msearch = $qf->{msearch};

    $musicdata{"MUSIC_ROOT"}       = int( $mpath eq "" );
    $musicdata{"MUSIC_LASTUPDATE"} = $main::MUSICUPDATE;
    $musicdata{"MUSIC_PATH"}       = encode_entities($mpath);

    my $music      = $self->getSystem()->musicLibrary();
    my $parent     = $music->getItem($mpath);
    my @elements   = $music->getChildren($parent);

    %musicdata = (%musicdata, $self->build_item_data("MUSIC", $parent));
    $musicdata{"MUSIC_UPDATED"}    = 1;


    my @music_loop_data = map { { $self->build_item_data("MUSIC", $_) } } @elements;

    $musicdata{"MUSIC_LOOP"} = \@music_loop_data;

    return \%musicdata;
}

###############################################################################
sub build_map {
    my ( $self, $qf, $params ) = @_;

    my $player = undef;
    $player = $self->zonePlayer($qf->{zone}) if $qf->{zone};

    my $updatenum = 0;
    $updatenum = $qf->{lastupdate} if ( $qf->{lastupdate} );

    my %map = ();

    # globals
    {
        my $globals = {};
        $globals->{"BASE_URL"}             = $self->baseURL();
        $globals->{"VERSION"}              = $self->version();
        $globals->{"LAST_UPDATE"}          = $self->lastUpdate();
        $globals->{"LAST_UPDATE_READABLE"} = localtime $self->lastUpdate();

        my @keys    = grep !/action|rand|mpath|msearch|link/, ( keys %$qf );
        $globals->{"ALL_ARG"} = join "&", map { "$_=$qf->{$_}" } @keys;

        $globals->{"MUSICDIR_AVAILABLE"} = 0;
        $globals->{"ZONES_LASTUPDATE"}   = $self->lastUpdate(); # FIXME
        $globals->{"ZONES_UPDATED"}      = ( $self->lastUpdate() > $updatenum );

        $map{GLOBALS_JSON} = to_json( $globals, { pretty => 1 } );
        %map = ( %map, %$globals );
    }

    if ( grep /^ZONES_/i, @$params ) {
        my @zones = map { $self->build_zone_data( $_, $updatenum, $player); } $self->players();
        $map{ZONES_LOOP} = \@zones;
        $map{ZONES_JSON} = to_json( \@zones, { pretty => 1 } );
    }

     if ( grep /^ALL_QUEUE_/i, @$params ) {
         my @queues = map { build_queue_data( $_, $updatenum ); } $self->getSystem()->players();
         $map{ALL_QUEUE_LOOP} = \@queues;
         $map{ALL_QUEUE_JSON} = to_json( \@queues, { pretty => 1 } );
     }

    if ( $player ) {
        my $queue = $self->build_queue_data( $player, $updatenum );
        $map{QUEUE_JSON} = to_json( $queue, { pretty => 1 } );
        %map = ( %map, %$queue );
    }

    if ( grep /^MUSIC_/i, @$params ) {
        my $music = $self->build_music_data( $qf, $updatenum );
        $map{MUSIC_JSON} = to_json( $music, { pretty => 1 } );
        %map = ( %map, %$music );
    }

    if ( $player ) {
        my $zone = $self->build_zone_data( $player, $updatenum, $player );
        %map = ( %map, %$zone );
    }

    # for (@$params) {
    #     croak "param \"" . uc($_) . "\" is unset in map but used in template\n map = " . Dumper(\%map) unless exists($map{uc($_)});
    # }

    return \%map;

}