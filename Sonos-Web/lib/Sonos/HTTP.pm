package Sonos::HTTP;

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
use URI::WithBase;
use File::Spec::Functions 'catfile';
use IO::Compress::Gzip qw(gzip $GzipError) ;
use MIME::Types;

require HTML::Template::Compiled;

###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $loop, $discover, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _discovery => $discover,
        _daemon => HTTP::Daemon->new(ReuseAddr => 1, ReusePort => 1, %args),
        _loop => $loop,
        _default_page => ($args{DefaultPage} || "status.xml"),
        _mime_types =>  MIME::Types->new,
    }, $class;


    my $handle = IO::Async::Listener->new(
         handle => $self->{_daemon},
         on_accept => sub { $self->handle_request(@_); }
    );

    $loop->add( $handle );

    print STDERR "Listening on " . $self->{_daemon}->url . "\n";

    return $self;
}

sub baseURL($self) {
    return $self->{_daemon}->url;
}

sub defaultURL($self) {
    return URI::WithBase->new($self->{_default_page}, $self->baseURL);
}

sub mimeTypeOf($self, $p) {
    return $self->{_mime_types}->mimeTypeOf($p);
}

###############################################################################
sub handle_request($self, $handle, $c) {
    my $r = $c->get_request;
    my $baseurl = $self->baseURL();

    # No r, just return
    return unless ( $r && $r->uri );

    my $uri  = $r->uri;
    my %qf   = $uri->query_form;
    my $path = $uri->path;

    if ( ( $path eq "/" ) || ( $path =~ /\.\./ ) ) {
        $c->send_redirect($self->defaultURL);
        $c->force_last_request;
        return;
    }

    # Find where on disk
    my $diskpath = catfile("html", $path);
    if ( ! -e $diskpath ) {
        $c->send_error(HTTP::Status::RC_NOT_FOUND);
        $c->force_last_request;
        return;
    }

    # File is a directory, redirect for the browser
    if ( -d $diskpath ) {
        $c->send_redirect(catfile($baseurl, $path, "index.html"));
        $c->force_last_request;
        return;
    }

    # File isn't HTML/XML/JSON, just send it back raw
    if (  $path !~ /\.(html|xml|json)/ )
    {
        $c->send_file_response($diskpath);
        $c->force_last_request;
        return;
    }

    my $handled = 0;

    if ( exists $qf{action} ) {
        $handled = handle_zone_action( $c, $r, $path ) if ( exists $qf{zone} );
        $handled ||= handle_action( $c, $r, $path );
    }

    if ( $qf{NoWait} ) {
        $handled = 1;
    }

    my $tmplhook;
    my @common_args = ( "*", \& send_tmpl_response, $c, $r, $diskpath, $tmplhook );
}

###############################################################################
sub handle_zone_action {
    my ($self, $c, $r, $path ) = @_;
    my %qf = $r->uri->query_form;
    my $mpath = decode( "UTF-8", $qf{mpath} );
    my $zone = $self->getPlayer($qf{zone});

    my %action_table (
        # ContentDirectory actions
        "Remove" => sub { $player->removeTrack( $qf{queue} ); return 4; },
        "RemoveAll" => sub { $player->removeAll() return 4; },

        # AVtransport Actions
        "Play" ) {
   "Pause" ) {
    "Stop" ) {
"ShuffleOn" ) {
q "ShuffleOff" ) {
 "RepeatOn" ) {
"RepeatOff" ) {
 "Seek" ) {

        # Render actions
 "MuteOn" ) {
"MuteOff" ) {
 "MuchSofter" ) {
   "Softer" ) {
 "Louder" ) {
   "MuchLouder" ) {
   "SetVolume" ) {
    elsif ( $qf{action} eq "Save" ) {
        upnp_avtransport_save( $zone, $qf{savename} );
        return 0;
    }
    elsif ( $qf{action} eq "AddMusic" ) {
        my $class = sonos_music_class($mpath);
        if ( sonos_is_radio($mpath) ) {
            sonos_avtransport_set_radio( $zone, $mpath );
            return 2;
        }
        elsif ( $class eq "object.item.audioItem" ) {
            sonos_avtransport_set_linein( $zone, $mpath );
            return 2;
        }
        else {
            sonos_avtransport_add( $zone, $mpath );
            return 4;
        }
    }
    elsif ( $qf{action} eq "DeleteMusic" ) {
        if ( sonos_music_class($mpath) eq "object.container.playlist" ) {
            my $entry = sonos_music_entry($mpath);
            upnp_content_dir_delete( $zone, $entry->{id} );
        }
        return 0;
    }
    elsif ( $qf{action} eq "PlayMusic" ) {
        my $class = sonos_music_class($mpath);
        if ( sonos_is_radio($mpath) ) {
            sonos_avtransport_set_radio( $zone, $mpath );
        }
        elsif ( $class eq "object.item.audioItem" ) {
            sonos_avtransport_set_linein( $zone, $mpath );
        }
        else {
            if ( !( $main::ZONES{$zone}->{AV}->{AVTransportURI} =~ /queue/ ) ) {
                sonos_avtransport_set_queue($zone);
            }
            upnp_avtransport_action( $zone, "RemoveAllTracksFromQueue" );
            sonos_avtransport_add( $zone, $mpath );
            upnp_avtransport_play($zone);
        }

        return 4;
    }
    elsif ( $qf{action} eq "LinkAll" ) {
        sonos_link_all_zones($zone);
        return 2;
    }
    elsif ( $qf{action} eq "Unlink" ) {
        sonos_unlink_zone( $qf{link} );
        return 2;
    }
    elsif ( $qf{action} eq "Link" ) {
        sonos_link_zone( $zone, $qf{link} );
    }
    else {
        return 0;
    }
    return 1;
}

###############################################################################
sub handle_action {
    my ( $c, $r, $path ) = @_;
    my %qf = $r->uri->query_form;


    if ( $qf{action} eq "ReIndex" ) {
        sonos_reindex();
    }
    elsif ( $qf{action} eq "Unlink" ) {
        sonos_unlink_zone( $qf{link} );
    }
    elsif ( $qf{action} eq "Wait" && $qf{lastupdate} ) {
        if ( $main::LASTUPDATE > $qf{lastupdate} ) {
            return 1;
        }
        else {
            return 5;
        }
    }
    else {
        return 0;
    }
    return 1;
}

###############################################################################
sub build_zone_data {
    my ( $self, $player, $updatenum, $active_player ) = @_;
    my %activedata;
    my $zoneName = $player->zoneName();
    my $lastupdate = -1;

    $activedata{HAS_ACTIVE_ZONE} = int( defined $active_player );
    $activedata{ACTIVE_ZONE}     = enc( $player->zoneName() );
    $activedata{ACTIVE_ZONEID}   = uri_escape($player->UDN());
    $activedata{ACTIVE_VOLUME}   = $player->getVolume();
    $activedata{ZONE_ACTIVE}     = int( $player == $active_player );

    $activedata{ACTIVE_LASTUPDATE} = $player->lastUpdate();
    $activedata{ACTIVE_UPDATED}    = ( $player->lastUpdate() > $updatenum );
    $activedata{ACTIVE_MUTED}      = $player->getMuted();

    my $curtrack     = $player->currentTrack();
    my $curtransport = $player->currentTransport();

    if ($curtrack) {
        $activedata{ACTIVE_ALBUMART} = uri_escape_utf8($curtrack->albumArtURI());
        $activedata{ACTIVE_NAME}    = enc( $curtrack->title() );
        $activedata{ACTIVE_ARTIST}  = enc( $curtrack->creator() );
        $activedata{ACTIVE_ALBUM}   = enc( $curtrack->album() );
        $activedata{ACTIVE_CONTENT} = enc( $curtrack->content() );
        $activedata{ACTIVE_LENGTH}  = $curtrack->lengthInSeconds();

        $activedata{ACTIVE_TRACK_NUM} = enc($curtrack->currentTrack());
        $activedata{ACTIVE_TRACK_TOT} = enc($curtrack->numberOfTracks());
        # $activedata{ACTIVE_TRACK_TOT_0} = ( $main::ZONES{$zone}->{AV}->{NumberOfTracks} == 0 );
        # $activedata{ACTIVE_TRACK_TOT_1} = ( $main::ZONES{$zone}->{AV}->{NumberOfTracks} == 1 );
        # $activedata{ACTIVE_TRACK_TOT_GT_1} = ( $main::ZONES{$zone}->{AV}->{NumberOfTracks} > 1 );
    }


    my $av = $player->avTransport();

    my $transportstate = $av->transportState();
    my %transport_states = ( "TRANSITIONING" => 3, "PAUSED_PLAYBACK" => 2, "PLAYING" => 1, "STOPPED" => 0);
    $activedata{"ACTIVE_MODE"} = $transport_states{$transportstate};
    $activedata{"ACTIVE_$_"}   = ($transportstate eq $_) for (keys %transport_states);

    my $playmode = $av->currentPlayMode();
    $activedata{ACTIVE_REPEAT} = $av->isRepeat();
    $activedata{ACTIVE_SHUFFLE} = $av->isShuffle();


    my $nexttrack = $av->nextTrack();
    if ($nexttrack) {
        $activedata{NEXT_NAME}   = enc( $nexttrack->{item}->{"dc:title"} );
        $activedata{NEXT_ARTIST} = enc( $nexttrack->{item}->{"dc:creator"} );
        $activedata{NEXT_ALBUM}  = enc( $nexttrack->{item}->{"upnp:album"} );
        $activedata{NEXT_ISSONG} = 1;
    }

    $activedata{ZONE_MODE}   = $activedata{ACTIVE_MODE};
    $activedata{ZONE_MUTED}  = $activedata{ACTIVE_MUTED};
    $activedata{ZONE_ID}     = $activedata{ACTIVE_ZONEID};
    $activedata{ZONE_NAME}   = $activedata{ACTIVE_ZONE};
    $activedata{ZONE_VOLUME} = $activedata{ACTIVE_VOLUME};
    $activedata{ZONE_ARG}    = "zone=$zoneName&";

    $activedata{ZONE_ICON} = $player->icon();
    $activedata{ZONE_LASTUPDATE} = $lastupdate;
    my $num_linked = $player->zoneSize();
    $activedata{ZONE_NUMLINKED} = $num_linked;
    $activedata{ZONE_FANCYNAME} = $activedata{ZONE_NAME};
    $activedata{ZONE_FANCYNAME} .= " + " . $num_linked if $num_linked;

    $activedata{ZONE_MEMBERS} = [
        map {
            {
                "ZONE_NAME" => $_->zoneName(),
                "ZONE_ID"   => $_->UDN(),
                "ZONE_LINKED" => int( ! $_->isCoordinator() ),
                "ZONE_ICON" => $_->icon(),
            }
        } @{$player->zoneMembers()}
    ];

    $activedata{ZONE_LINKED}    = ! $player->isCoordinator();
    $activedata{ZONE_LINK}      = $player->coordinator()->UDN();
    $activedata{ZONE_LINK_NAME} = $player->coordinator()->zoneName();

    $activedata{ACTIVE_JSON} = to_json( \%activedata, { pretty => 1 } );

    return \%activedata;
}

###############################################################################
sub build_queue_data {
    my ($self, $player, $updatenum ) = @_;

    my %queuedata;

    $queuedata{QUEUE_ZONE}       = $player->zoneName;
    $queuedata{QUEUE_ZONEID}     = uri_escape_utf8($player->UDN);
    $queuedata{QUEUE_LASTUPDATE} = $player->lastQueueUpdate();
    $queuedata{QUEUE_UPDATED}    = ( $player->lastQueueUpdate() > $updatenum );

    my @loop_data = map {
        {
            "QUEUE_NAME"      => enc( $_->{"dc:title"} ),
            "QUEUE_ALBUM"     => enc( $_->{"upnp:album"} ),
            "QUEUE_ARTIST"    => enc( $_->{"dc:creator"} ),
            "QUEUE_TRACK_NUM" => enc( $_->{"upnp:originalTrackNumber"} ),
            "QUEUE_ALBUMART"  => enc( $_->{"upnp:albumArtURI"} ),
            "QUEUE_ID"        =>      $_->{id}
        }
    } $player->queue();

    $queuedata{QUEUE_LOOP} = \@loop_data;
    $queuedata{QUEUE_JSON} = to_json( \@loop_data, { pretty => 1 } );

    return \%queuedata;
}

sub build_music_data {
    my $self      = shift;
    my $qf        = shift;
    my $updatenum = shift;
    my %musicdata;

    my @music_loop_data = ();
    my @page_loop_data  = ();

    my $albumart = "";

    my $mpath = "";
    $mpath = $qf->{mpath} if ( defined $qf->{mpath} );
    $mpath = ""           if ( $mpath eq "/" );
    my $msearch = $qf->{msearch};
    my $item    = sonos_music_entry($mpath);

    $musicdata{"MUSIC_ROOT"}       = int( $mpath eq "" );
    $musicdata{"MUSIC_LASTUPDATE"} = $main::MUSICUPDATE;
    $musicdata{"MUSIC_PATH"}       = enc($mpath);

    $musicdata{"MUSIC_NAME"}    = enc( $item->title  );
    $musicdata{"MUSIC_ARTIST"}  = enc( $item->creator);
    $musicdata{"MUSIC_ALBUM"}   = enc( $item->album  );
    $musicdata{"MUSIC_CLASS"}   = enc( $item->class  );
    $musicdata{"MUSIC_CONTENT"} = uri_escape_utf8( $item->content  );
    $musicdata{"MUSIC_PARENT"}  = uri_escape_utf8( $item->parentID );
    $musicdata{"MUSIC_ARG"}     = uri_escape_utf8( $item->id );
    $musicdata{"MUSIC_ISSONG"}  = int( $item->isSong() );
    $musicdata{"MUSIC_ISRADIO"} = int( $item->isRadio() );
    $musicdata{"MUSIC_ISALBUM"} = int( $item->isAlbum() );
    $musicdata{"MUSIC_ISFAV"}   = int( $item->isFav() );

    $musicdata{"MUSIC_UPDATED"}    = ( $mpath ne ""
          || ( !$qf->{NoWait} && ( $main::MUSICUPDATE > $updatenum ) ) );

    my $music_arg = $musicdata{MUSIC_ARG} = "mpath=" . uri_escape_utf8($mpath);

    my $elements = $self->getSystem()->globalCache()->getItems($mpath);
    foreach my $music ( @{$elements} ) {
        next if ( $msearch && $music->title() !~ m/$msearch/i );

        # FILL IN SAME as above
    }

    $musicdata{"MUSIC_LOOP"} = \@music_loop_data;

    return \%musicdata;
}

###############################################################################
sub build_map {
    my ( $self, $qf, $params ) = @_;

    my $player = undef;
    $player = $self->getSystem()->getPlayer($qf->{zone}) if $qf->{zone};

    my $updatenum = 0;
    $updatenum = $qf->{lastupdate} if ( $qf->{lastupdate} );

    my %map = ();

    # globals
    {
        my $globals = {};
        $globals->{"BASE_URL"}             = $self->baseURL();
        $globals->{"VERSION"}              = $main::VERSION;
        $globals->{"LAST_UPDATE"}          = $main::LASTUPDATE;
        $globals->{"LAST_UPDATE_READABLE"} = localtime $main::LASTUPDATE;

        my @keys    = grep !/action|rand|mpath|msearch|link/, ( keys %$qf );
        my $all_arg = "";
        $all_arg .= "$_=$qf->{$_}&" for @keys;
        $globals->{"ALL_ARG"} = $all_arg;

        $globals->{"MUSICDIR_AVAILABLE"} = !( $main::MUSICDIR eq "" );
        $globals->{"ZONES_LASTUPDATE"}   = $main::ZONESUPDATE;
        $globals->{"ZONES_UPDATED"}      = ( $main::ZONESUPDATE > $updatenum );

        $map{GLOBALS_JSON} = to_json( $globals, { pretty => 1 } );
        %map = ( %map, %$globals );
    }

    if ( grep /^ZONES_/i, @$params ) {
        my @zones = map { build_zone_data( $_, $updatenum, $qf->{zone} ); } $self->system()->zones();
        $map{ZONES_LOOP} = \@zones;
        $map{ZONES_JSON} = to_json( \@zones, { pretty => 1 } );
    }

    if ( grep /^ALL_QUEUE_/i, @$params ) {
        my @queues = map { build_queue_data( $_, $updatenum ); } $self->getSystem()->getPlayers();
        $map{ALL_QUEUE_LOOP} = \@queues;
        $map{ALL_QUEUE_JSON} = to_json( \@queues, { pretty => 1 } );
    }

    if ( exists $qf->{zone} ) {
        my $queue = build_queue_data( $qf->{zone}, $updatenum );
        $map{QUEUE_JSON} = to_json( $queue, { pretty => 1 } );
        %map = ( %map, %$queue );
    }

    if ( grep /^MUSIC_/i, @$params ) {
        my $music = build_music_data( $qf, $updatenum );
        $map{MUSIC_JSON} = to_json( $music, { pretty => 1 } );
        %map = ( %map, %$music );
    }

    if ( exists $qf->{zone} ) {
        my $zone = build_zone_data( $qf->{zone}, $updatenum, $qf->{zone} );
        %map = ( %map, %$zone );
    }

    return \%map;

}

###############################################################################
sub send_tmpl_response {
    my ( $what, $zone, $c, $r, $diskpath, $tmplhook ) = @_;

    my %qf = $r->uri->query_form;

    # One of our templates, now fill in the parts we know
    my $template = HTML::Template::Compiled->new(
        filename          => $diskpath,
        die_on_bad_params => 0,
        global_vars       => 1,
        use_query         => 1,
        loop_context_vars => 1
    );
    my @params = $template->param();
    my $map    = build_map( \%qf, \@params );
    $template->param(%$map);

    my $content_type = $self->mimeTypeOf($diskpath);
    my $output = encode( 'utf8', $template->output );
    my $gzoutput;
    my $status   = gzip $output => $gzoutput;
    my $handled = HTTP::Response->new(
        200, undef,
        [
            Connection         => "close",
            "Content-Type"     => $content_type,
            "Pragma"           => "no-cache",
            "Content-Encoding" => "gzip",
            "Cache-Control"    =>
              "no-store, no-cache, must-revalidate, post-check=0, pre-check=0"
        ],
        $gzoutput
    );
    $c->send_response($handled);
    $c->force_last_request;
    $c->close;
}
