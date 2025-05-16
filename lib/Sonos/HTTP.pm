package Sonos::HTTP;

use v5.36;
use strict;
use warnings;


use File::Slurp qw( read_file );

use Net::Async::HTTP::Server ();
use HTTP::Status ();
use HTML::Entities ();
use URI::Escape ();
use Encode qw( decode encode );
use File::Spec::Functions qw( catfile );
use MIME::Types ();
use Scalar::Util::Numeric qw( isint );
use Carp qw( carp );


require Sonos::HTTP::Template;
require Sonos::HTTP::Builder;

###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $loop, $system, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _system => $system,
        _daemon => undef,
        _handlers => {},
        _loop => $loop,
        _default_page => ($args{DefaultPage} || "index.html"),
        _mime_types =>  MIME::Types->new,
    }, $class;


    # HTTP Handlers
    $self->registerHandler("/getaa", sub { $self->sendAlbumartResponse(@_) });
    $self->registerHandler("/hello", sub { $self->sendHello(@_) });
    $self->registerHandler("/api", sub { $self->restAPI(@_) });

    my $httpserver = Net::Async::HTTP::Server->new(
        on_request => sub { $self->handleRequest(@_); }
    );

    $loop->add( $httpserver );

    $httpserver->listen(
        addr => {
            family   => "inet",
            socktype => "stream",
            port     => 9999,
        },
        on_listen_error => sub { die "Cannot listen - $_[-1]\n" }
    );

    printf STDERR  "Listening on http://%s:%d\n",
        $httpserver->read_handle->sockhost,
        $httpserver->read_handle->sockport;

    $self->{_daemon} = $httpserver;

    return $self;
}

sub system($self) {
    return $self->{_system};
}

sub player($self, $name_or_uuid) {
    return $self->system()->player($name_or_uuid);
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
    $self->system()->log("httpd", @args);
}


sub registerHandler($self, $path, $callback) {
    $self->{_handlers}->{$path} = $callback;
}

sub validateRequest($self, $r) {
   unless ($self->system() and $self->system()->populated()) {
        return $self->sendError($r, 501, "Waiting for discovery");
    }

    my %qf     = $r->query_form;
    my $player;

    if (exists $qf{zone}) {
        my $zone   = $qf{zone};
        $player = $self->player($zone);
        return $self->sendError($r, 404, "No such player: $zone") unless $player;
    }

    if (exists $qf{mpath}) {
        my $path = decode( "UTF-8", $qf{mpath} );
        my $item = $self->system()->musicLibrary()->item($path);
        return $self->sendError($r, 404, "No such music item: $path") unless $item;
    }


    if (exists $qf{queue}) {
        my $path = decode( "UTF-8", $qf{queue} );
        return $self->sendError($r, 404, "queue=$path requires a zone=") unless $player;

        my $item = $player->queue()->item($path);
        return $self->sendError($r, 404, "No such queue item: $path") unless $item;
    }

    if (exists $qf{what}) {
        my $what = $qf{what};
        my @allowed_requests = qw(system music zones zone info queue none all);
        unless (grep { $what eq $_ } @allowed_requests) {
            return $self->sendError($r, 404, "Request \"$what\" unknown. Known: " . (join ", ", @allowed_requests));
        }

        my @requires_zone = qw(zone queue);
        if ((grep { $what eq $_ } @requires_zone) && !$player) {
            return $self->sendError($r, 404, "Request \"$what\" requires a zone= argument");
        }
    }

    return 0;
}
sub validateAction($self, $r, $dispatch) {
    my %qf     = $r->query_form;
    my $action = lc $qf{action};

    unless (exists $dispatch->{$action}) {
        return $self->sendError($r, 404, "Unknown action \"$action\"");
    }

    my ($service, $code, @needs) = @{$dispatch->{$action}};

    unshift @needs, "zone" unless grep { $_ eq "nozone" } @needs;
    @needs = grep { $_ ne "nozone" } @needs;

    for (@needs) {
        return $self->sendError($r, 404, "Action \"$action\" requires a $_= argument")
            unless (exists $qf{$_});
    }

    return 0;
}

sub handleRequest($self, $server, $r) {
    my $path  = $r->path;
    my %qf   = $r->query_form;

    $self->validateRequest($r) && return;

    $self->log("handling request: ", $r->as_http_request()->uri);

    if (my $callback = $self->{_handlers}->{$path}) {
        $self->log("  handler: ", $path);
        return $callback->($r);
    }

    if ( ( $path eq "/" ) || ( $path =~ /\.\./ ) ) {
        my $redirect = $self->defaultPage;
        return $self->sendRedirect($r, $redirect);
    }

    # Find where on disk
    my $diskpath = $self->diskpath($path);

    # Find icons
    if ( ( $path =~ m@/icons/@ ) && ! -e $diskpath ) {
        my @images = glob("$diskpath.*");
        carp("Mulitple icons found for $path:\n" . @images) if (scalar @images) > 1;
        carp("No icon found for $path") unless @images;
        $diskpath = $images[0] if scalar @images == 1;
    }

    return $self->sendError($r, HTTP::Status::RC_NOT_FOUND, "Could not find $diskpath") unless -e $diskpath;

    # File is a directory, redirect for the browser
    if ( -d $diskpath ) {
        my $redirect = catfile($path, "index.html");
        return $self->sendRedirect($r, $redirect);
    }

    # File isn't HTML/XML/JSON/JS, just send it back raw
    if (  $path !~ /\.(html|xml|js|json)$/ )
    {
        return $self->sendFileResponse($r, $diskpath);
    }

    $self->action($r, sub { $self->sendTemplateResponse($r, $diskpath) });
}

###############################################################################
sub action {
    my ($self, $r, $do_after) = @_;

    my %qf = $r->query_form;
    my $action = $qf{action};

    return $do_after->() unless $action;

    my $lastupdate = $qf{lastupdate};
    $lastupdate = -1 unless isint($lastupdate);

    my $system = $self->system();
    my $player = $self->player($qf{zone}) if $qf{zone};
    my $av = $player->avTransport() if $player;
    my $render = $player->renderingControl() if $player;
    my $contentdir = $player->contentDirectory() if $player;

    my $link = $self->player($qf{link}) if $qf{link};
    my $topo = $link->zoneGroupTopology() if $link;

    my $music = $self->system()->musicLibrary();
    my $mpath = decode( "UTF-8", $qf{mpath} );
    my $mitem = $music->item($mpath) if $mpath;

    my $qpath = decode( "UTF-8", $qf{queue} );
    my $qitem = $player->queue()->item($qpath) if $qpath and $player;

    my $dispatch = {
        "start"      => [ $av, sub { $av->start() } ],
        "pause"      => [ $av, sub { $av->pause() } ],
        "stop"       => [ $av, sub { $av->stop() } ],

        "muteon"     => [ $render, sub { $render->setMute(1) } ],
        "muteoff"    => [ $render, sub { $render->setMute(0) }  ],

        "muchsofter" => [ $render, sub { $render->changeVolume(-5); },],
        "softer"     => [ $render, sub { $render->changeVolume(-1); },],
        "louder"     => [ $render, sub { $render->changeVolume(+1); },],
        "muchlouder" => [ $render, sub { $render->changeVolume(+5); },],
        "setvolume"  => [ $render, sub { $render->setVolume($qf{volume}); }, "volume"],
        "volume"     => [ $render, sub { $render->setVolume($qf{volume}); }, "volume"],

        "next"        => [ $av, sub { $av->next() } ],
        "previous"    => [ $av, sub { $av->previous() } ],

        "repeatoff"   => [ $av, sub { $av->setRepeat(0) } ],
        "repeaton"    => [ $av, sub { $av->setRepeat(1); } ],
        "shuffleoff"  => [ $av, sub { $av->setShuffle(0); } ],
        "shuffleon"   => [ $av, sub { $av->setShuffle(1); } ],

        # queue
        "removeall"   => [ $av, sub {
            $av->removeAllTracksFromQueue();
        } ],
        "add"    => [ $av, sub {
            $av->addToQueue($qf{mpath}, 1);
         }, "mpath", ],
        "play"   => [ $av, sub {
            $av->playMusic($qf{mpath})
        }, "mpath", ],
        "deletemusic" => [ $av, sub {
            $contentdir->destroyObject($qitem);
        }, "mpath", ],
        "save"        => [ $av, sub {
            $av->saveQueue($qf{savename});
        }, "savename", ],

        "remove"      => [ $av, sub {
            $av->RemoveTrackFromQueue($qitem->id())
        }, "queue", ],
        "seek"        => [ $av, sub {
            $av->seekInQueue($qitem->id());
        }, "queue", ],

        # wait for update, unless already happened
        "wait"       => [ $system, sub { $system->lastUpdate() <= $lastupdate; }, 'nozone', 'lastupdate' ],

        # Browse/Search music data
        "browse"     => [ undef, sub { return 0; }, "nozone" ],
        "search"     => [ undef, sub { return 0; }, "nozone", "msearch" ],

        # No-op
        "none"     => [ undef, sub { return 0; }, "nozone" ],

        "linkall"     => [ $system, sub { $system->linkAllZones($player); }, "nozone" ],
        "link"        => [ $topo, sub { $topo->linkToZone($qf{zone}); }, "link", ],
        "unlink"      => [ $topo, sub { $topo->unlink(); }, "nozone", "link", ],
    };

    $self->validateAction($r, $dispatch) && return 0;

    my ($service, $code) = @{$dispatch->{lc $action}};

    my $nowait = !$code->() || $qf{nowait};

    # do immediately if $nowait
    return $do_after->() if ($nowait);

    # delay the response until the action
    # has taken effect
    $service->onUpdate($do_after);
}

###############################################################################
sub sendTemplateResponse($self, $r, $diskpath) {
    my %qf = $r->query_form;

    # One of our templates, now fill in the parts we know
    my $template = Sonos::HTTP::Template->new($self->system(), $diskpath, \%qf);
    my $content_type = $self->mimeTypeOf($diskpath);
    my $output = encode( 'utf8', $template->output );
    my $content_length = length $output;
    my $response = HTTP::Response->new(
        200, undef,
        [
            "Content-Type"     => $content_type,
            "Content-Length"   => $content_length,
        ],
        $output
    );
    $r->respond($response);
}

sub sendAlbumartResponse($self, $r) {
    my $uri =  $r->as_http_request()->uri();
    my ($sha, $mime_type, $blob, $filename) = $self->system()->albumArtCache()->get($uri);

    return $self->sendError($r, 404, "Album art not found")
        unless defined($blob);

    my $content_length = length $blob;
    my $response = HTTP::Response->new(200, undef, [
        "Content-Type" => $mime_type,
        "Content-Length" => $content_length,
        # "Content-Disposition" => "attachment; filename=\".$filename\"",
        ], $blob);
    $r->respond($response);

    return 1;
}

sub sendFileResponse($self, $r, $diskpath) {
    my $blob = read_file($diskpath);
    my $content_length = length $blob;
    my $mime_type = $self->mimeTypeOf($diskpath);
    my $response = HTTP::Response->new(200, undef, [
        "Content-Type" => $mime_type,
        "Content-Length" => $content_length,
    ], $blob);
    $r->respond( $response );
    $self->log("  raw - done");

    return 1;
}

sub sendRedirect($self, $r, $to) {
    my $response = HTTP::Response->new(301, undef, ["Location" => $to,"Content-Length" => 0]);
    $r->respond( $response );
    $self->log("  redirect to $to");

    return 1;
}

sub sendError($self, $r, $code, $message = undef) {
    my $response = HTTP::Response->new($code, $message, ["Content-Length" => 0]);
    $r->respond( $response );
    $self->log("  error: $code ($message)");

    return 1;
}

sub sendHello($self, $req) {
    my $response = HTTP::Response->new( 200 );
    $response->add_content( "Hello, world!\n" );
    $response->content_type( "text/plain" );
    $response->content_length( length $response->content );
    $req->respond( $response );

    return 1;
}

sub restAPI($self, $r) {
    $self->action($r, sub {
        my %qf = $r->query_form;
        my $builder = Sonos::HTTP::Builder->new($self->system(), \%qf);

        my $what = $qf{"what"} || "all";
        my $method = "build_" . $what . "_data";
        my $data = $builder->$method();
        my $json = $builder->to_json($data);

        my $response = HTTP::Response->new( 200 );
        $response->add_content( $json );
        $response->content_type( "application/json; charset=UTF-8" );
        $response->content_length( length $response->content );
        $r->respond( $response );
    });

    return 1;
}