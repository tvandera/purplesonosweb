package Sonos::HTTP;

use v5.36;
use strict;
use warnings;


use File::Slurp qw(read_file);

use Net::Async::HTTP::Server;
use HTTP::Status ":constants";
use HTML::Entities;
use URI::Escape;
use Encode qw(encode decode);
use File::Spec::Functions 'catfile';
use MIME::Types;

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
    $self->register_handler("/getaa", sub { $self->send_albumart_response(@_) });
    $self->register_handler("/hello", sub { $self->send_hello(@_) });
    $self->register_handler("/api", sub { $self->rest_api(@_) });

    my $httpserver = Net::Async::HTTP::Server->new(
        on_request => sub { $self->handle_request(@_); }
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

sub version($self) {
    return "0.99";
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


sub register_handler($self, $path, $callback) {
    $self->{_handlers}->{$path} = $callback;
}

sub validateRequest($self, $r) {
   unless ($self->system() and $self->system()->populated()) {
        return $self->send_error($r, 501, "Waiting for discovery");
    }

    my %qf     = $r->query_form;
    my $player;

    if (exists $qf{zone}) {
        my $zone   = $qf{zone};
        $player = $self->player($zone);
        return $self->send_error($r, 404, "No such player: $zone") unless $player;
    }

    if (exists $qf{mpath}) {
        my $path = decode( "UTF-8", $qf{mpath} );
        my $item = $self->system()->musicLibrary()->item($path);
        return $self->send_error($r, 404, "No such music item: $path") unless $item;
    }


    if (exists $qf{queue}) {
        my $path = decode( "UTF-8", $qf{queue} );
        return $self->send_error($r, 404, "queue=$path requires a zone=") unless $player;

        my $item = $player->queue()->item($path);
        return $self->send_error($r, 404, "No such queue item: $path") unless $item;
    } 

    if (exists $qf{what}) {
        my $what = $qf{what};
        my @allowed_requests = qw(globals music zones zone queue none all);
        unless (grep { $what eq $_ } @allowed_requests) {
            return $self->send_error($r, 404, "Request \"$what\" unknown. Known: " . (join ", ", @allowed_requests));
        }

        my @requires_zone = qw(zone queue);
        if ((grep { $what eq $_ } @requires_zone) && !$player) {
            return $self->send_error($r, 404, "Request \"$what\" requires a zone= argument");
        }
    }

    return 0;
}
sub validateAction($self, $r, $dispatch) {
    my %qf     = $r->query_form;
    my $action = $qf{action};

    unless (exists $dispatch->{$action}) {
        return $self->send_error($r, $404, "Unknown action \"$action\"");
    }

    my ($service, $code, @needs) = @{$dispatch->{$action}};

    unshift @needs, "zone" unless grep { $_ eq "nozone" } @needs;
    @needs = grep { $_ ne "nozone" } @needs;

    for (@needs) {
        return $self->send_error($r, 404, "Action \"$action\" requires a $_= argument")
            unless (exists $qf{$_});
    }

    return 0;
}

sub handle_request($self, $server, $r) {
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
        return $self->send_redirect($r, $redirect);
    }

    # Find where on disk
    my $diskpath = $self->diskpath($path);
    return $self->send_error($r, HTTP::Status::RC_NOT_FOUND, "Could not find $diskpath") unless -e $diskpath;

    # File is a directory, redirect for the browser
    if ( -d $diskpath ) {
        my $redirect = catfile($path, "index.html");
        return $self->send_redirect($r, $redirect);
    }

    # File isn't HTML/XML/JSON/JS, just send it back raw
    if (  $path !~ /\.(html|xml|js|json)$/ )
    {
        return $self->send_file_response($r, $diskpath);
    }

    $self->action($r, sub { $self->send_tmpl_response($r, $diskpath) });
}

###############################################################################
sub action {
    my ($self, $r, $do_after) = @_;

    my %qf = $r->query_form;
    my $action = $qf{action};

    return $do_after->() unless $action;

    my $lastupdate = $qf{lastupdate};

    my $player = $self->player($qf{zone}) if $qf{zone};
    my $av = $player->avTransport() if $player;
    my $render = $player->renderingControl() if $player;
    my $contentdir = $player->contentDirectory() if $player;
    my $music = $self->system()->musicLibrary();

    my $mpath = decode( "UTF-8", $qf{mpath} );
    my $mitem = $music->item($mpath) if $mpath;

    my $qpath = decode( "UTF-8", $qf{queue} );
    my $qitem = $player->queue()->item($qpath) if $qpath;

    my $dispatch = {
        "Play"       => [ $av, sub { $av->play() } ],
        "Pause"      => [ $av, sub { $av->pause() } ],
        "Stop"       => [ $av, sub { $av->stop() } ],

        "MuteOn"     => [ $render, sub { $render->setMute(1) } ],
        "MuteOff"    => [ $render, sub { $render->setMute(0) }  ],

        "MuchSofter" => [ $render, sub { $render->changeVolume(-5); },],
        "Softer"     => [ $render, sub { $render->changeVolume(-1); },],
        "Louder"     => [ $render, sub { $render->changeVolume(+1); },],
        "MuchLouder" => [ $render, sub { $render->changeVolume(+5); },],
        "SetVolume"  => [ $render, sub { $render->setVolume($qf{volume}); }, "volume"],

        "Next"        => [ $av, sub { $av->next() } ],
        "Previous"    => [ $av, sub { $av->previous() } ],

        "RepeatOff"   => [ $av, sub { $av->setRepeat(0) } ],
        "RepeatOn"    => [ $av, sub { $av->setRepeat(1); } ],
        "ShuffleOff"  => [ $av, sub { $av->setShuffle(0); } ],
        "ShuffleOn"   => [ $av, sub { $av-setShuffle(1); } ],

        # queue
        "RemoveAll"   => [ $av, sub { 
            $av->removeAllTracksFromQueue();
        } ],
        "AddMusic"    => [ $av, sub { 
            $av->removeAllTracksFromQueue();
            $av->addURI($qf{mpath}, 1);
         }, "mpath", ],
        "PlayMusic"   => [ $av, sub {
            $av->removeAllTracksFromQueue();
            $av->addURI($qf{mpath});
            $av->play();
        }, "mpath", ],
        "DeleteMusic" => [ $av, sub {
            $contentdir->destroyObject($qitem);
        }, "mpath", ],
        "Save"        => [ $av, sub { 
            $av->saveQueue($qf{savename});
        }, "savename", ],

        "Remove"      => [ $av, sub {
            $av->RemoveTrackFromQueue($qitem->id())
        }, "queue", ],
        "Seek"        => [ $av, sub {
            $av->seekInQueue($qitem->id());
            $av->setQueue();
        }, "queue", ],

        # wait for update, unless already happened
        "Wait"       => [ $player, sub { $player->lastUpdate() <= $lastupdate; }, 'lastupdate' ],

        # Browse/Search music data
        "Browse"     => [ undef, sub { return 0; }, "nozone" ],
        "Search"     => [ undef, sub { return 0; }, "nozone", "msearch" ],

        # No-op
        "None"     => [ undef, sub { return 0; }, "nozone" ],

        "LinkAll"     => [ "nozone" ],
        "Link"        => [ "zone", "link", ],
        "Unlink"      => [ "zone", "link", ],
    };

    $self->validateAction($r, $dispatch) && return 0;


    my ($service, $code) = @{$dispatch->{$action}};

    my $nowait = !$code->() || $qf{NoWait};

    # delay send_tmpl, or do immediately
    return $do_after->() if ($nowait);

    $service->onUpdate($do_after);
}

###############################################################################
sub send_tmpl_response($self, $r, $diskpath) {
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

sub send_albumart_response($self, $r) {
    my $uri =  $r->as_http_request()->uri();
    my ($sha, $mime_type, $blob, $filename) = $self->system()->albumArtCache()->get($uri);

    return $self->send_error($r, 404, "Album art not found")
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

sub send_file_response($self, $r, $diskpath) {
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

sub send_redirect($self, $r, $to) {
    my $response = HTTP::Response->new(301, undef, ["Location" => $to,"Content-Length" => 0]);
    $r->respond( $response );
    $self->log("  redirect to $to");

    return 1;
}

sub send_error($self, $r, $code, $message = undef) {
    my $response = HTTP::Response->new($code, $message, ["Content-Length" => 0]);
    $r->respond( $response );
    $self->log("  error: $code ($message)");

    return 1;
}

sub send_hello($self, $req) {
    my $response = HTTP::Response->new( 200 );
    $response->add_content( "Hello, world!\n" );
    $response->content_type( "text/plain" );
    $response->content_length( length $response->content );
    $req->respond( $response );

    return 1;
}

sub rest_api($self, $r) {
    $self->action($r, sub {
        my %qf = $r->query_form;
        my $builder = Sonos::HTTP::Builder->new($self->system(), \%qf);

        my $what = $qf{"what"} || "zones";
        my $method = "build_" . $what . "_data";
        my $data = $builder->$method();
        my $json = $builder->to_json($data);

        my $response = HTTP::Response->new( 200 );
        $response->add_content( $json );
        $response->content_type( "application/json" );
        $response->content_length( length $response->content );
        $r->respond( $response );
    });

    return 1;
}