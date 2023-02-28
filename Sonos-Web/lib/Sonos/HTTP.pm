package Sonos::HTTP;

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);
use Data::Dumper;
use Carp;

use File::Slurp qw(read_file);

use Net::Async::HTTP::Server;
use HTTP::Status ":constants";
use HTML::Entities;
use URI::Escape;
use Encode qw(encode decode);
use File::Spec::Functions 'catfile';
use MIME::Types;

require Sonos::HTTP::Template;
require Sonos::HTTP::MapBuilder;

###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $loop, $discover, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _discovery => $discover,
        _daemon => undef,
        _handlers => {},
        _loop => $loop,
        _default_page => ($args{DefaultPage} || "index.html"),
        _mime_types =>  MIME::Types->new,
    }, $class;


    # HTTP Handlers
    $self->register_handler("/getaa", sub { $self->send_albumart_response(@_) });
    $self->register_handler("/getAA", sub { $self->send_albumart_response(@_) });
    $self->register_handler("/hello", sub { $self->send_hello(@_) });


    for (qw(globals action zone music active)) {
        $self->register_handler("/api/$_", sub { $self->rest_api(@_) });
    }

    my $httpserver = Net::Async::HTTP::Server->new(
        on_request => sub {
            $self->handle_request(@_);
        }
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
    return $self->{_discovery};
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
    INFO sprintf("[%12s]: ", "httpd"), @args;
}


sub register_handler($self, $path, $callback) {
    $self->{_handlers}->{$path} = $callback;
}

sub sanitizeRequest($self, $r) {
    unless ($self->system() and $self->system()->populated()) {
        return $self->send_error($r, 501, "Waiting for discovery");
    }

    my %qf     = $r->query_form;
    my $player = undef;
    my $zone   = undef;
    my $music  = undef;

    if (exists $qf{zone}) {
        $zone   = $qf{zone};
        $player = $self->player($zone);
        return $self->send_error($r, 404, "No such player: $zone") unless $player;
    }


    if (exists $qf{mpath}) {
        my $mpath = decode( "UTF-8", $qf{mpath} );
           $music = $self->system()->musicLibrary()->item($mpath);
        return $self->send_error($r, 404, "No such music item: $mpath") unless $music;
    }

    if (exists $qf{action}) {
        my $action = $qf{action};

        # requires zone= argument, but nothing else
        my @noarg_actions = qw(
            LinkAll

            Louder MuchLouder MuchSofter SetVolume Softer
            MuteOff MuteOn

            Next Previous
            Pause Play
            RepeatOff RepeatOn
            ShuffleOff ShuffleOn

            RemoveAll
        );

        if (grep($action, @noarg_actions) && not $player) {
            return $self->send_error($r, 404, "Action \"$action\" requires a zone= argument");
        }


        # require a zone= argument + something else
        my %zone_actions = (
            "Link"      => [ "link", ],
            "Unlink"    => [ "link", ],
            "Remove"    => [ "queue", ],
            "Seek"      => [ "queue", ],
            "AddMusic"  => [ "mpath", ],
            "PlayMusic" => [ "mpath", ],
            "Save"      => [ "savename", ],
        );

        if (exists $zone_actions{$action}) {
            return $self->send_error($r, 404, "Action \"$action\" requires a zone= argument") unless $player;

            my @needs = @{$zone_actions{$action}};
            for (@needs) {
                return $self->send_error($r, 404, "Action \"$action\" requires a $_= argument") unless exists $qf{$_};
            }
        }

        # These actions DO NOT require a zone= argument
        my %nozone_actions = (
            "DeleteMusic" => [ "mpath", ],
            "Browse" => [ "mpath", ],
            "ReIndex" => [],
            "Wait" => [],
        );

        if (exists $nozone_actions{$action}) {
            my @needs = @{$nozone_actions{$action}};
            for (@needs) {
                return $self->send_error($r, 404, "Action \"$action\" requires a $_= argument") unless exists $qf{$_};
            }
        }
    }


    return 0;
}

sub handle_request($self, $server, $r) {
    my $path  = $r->path;
    my %qf   = $r->query_form;

    $self->sanitizeRequest($r) && return;

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

    if ( exists $qf{action} ) {
        my $when_updated = sub { $self->send_tmpl_response($r, $diskpath) };
        $self->action($r, $when_updated);
    } else {
        $self->send_tmpl_response($r, $diskpath);
    }

}

###############################################################################
sub action {
    my ($self, $r, $send_update) = @_;

    my %qf = $r->query_form;
    my $mpath = decode( "UTF-8", $qf{mpath} );
    my $action = $qf{action};
    my $lastupdate = $qf{lastupdate};

    my $player = $self->player($qf{zone}) if $qf{zone};
    my $av = $player->avTransport() if $player;
    my $render = $player->renderingControl() if $player;


# These actions require a zone= argument
# ======================================

# zones: Link(zone=..&link=..) LinkAll Unlink(zone=..&link=..)

# renderingcontrol volume: Louder MuchLouder MuchSofter SetVolume Softer
# renderingcontrol mute/unmute: MuteOff MuteOn

# avtransport nav: Next Previous
# avtransport state: Pause Play
# avtransport repeat: RepeatOff RepeatOn
# avtransport shuffle: ShuffleOff ShuffleOn

# queue remove: Remove (queue=Q:0/xx) RemoveAll
# queue nav: Seek (queue=Q:0/xx)
# queue add: AddMusic PlayMusic (mpath=...)
# queue save: Save (savename="My Saved Queue")

# These actions DO NOT require a zone= argument
# =============================================

# music library: DeleteMusic(mpath=playlist) Browse(mpath=...) ReIndex
# other: Wait

    my %dispatch = (
        "Play"       => [ $av, sub { $av->play() } ],
        "Pause"      => [ $av, sub { $av->pause() } ],
        "Stop"       => [ $av, sub { $av->stop() } ],

        "MuteOn"     => [ $render, sub { $render->setMute(1) } ],
        "MuteOff"    => [ $render, sub { $render->setMute(0) }  ],

        "MuchSofter" => [ $render, sub { $render->changeVolume(-5); },],
        "Softer"     => [ $render, sub { $render->changeVolume(-1); },],
        "Louder"     => [ $render, sub { $render->changeVolume(+1); },],
        "MuchLouder" => [ $render, sub { $render->changeVolume(+5); },],

        # wait for update, unless already happened
        "Wait"       => [ $player, sub { $player->lastUpdate() <= $lastupdate; } ],

        # Browse music data
        "Browse"     => [ undef, sub { return 0; } ],
    );

    carp "Unknown action \"$action\"" unless exists $dispatch{$action};

    my ($service, $code) = @{$dispatch{$action}};

    my $nowait = !$code->() || $qf{NoWait};

    # delay send_tmpl, or do immediately
    if ($nowait) {
        $send_update->();
    } else {
        $service->onUpdate($send_update);
    }

    return $nowait;
}

###############################################################################
sub handle_action {
    my ($self,  $r ) = @_;
    my %qf = $r->query_form;


    if ( $qf{action} eq "ReIndex" ) {
        sonos_reindex();
    }
    elsif ( $qf{action} eq "Unlink" ) {
        sonos_unlink_zone( $qf{link} );
    }
    elsif ( $qf{action} eq "Wait" && $qf{lastupdate} ) {
        return ( $self->system()->lastUpdate() > $qf{lastupdate} ) ? 1 : 5;
    }
    else {
        return 0;
    }
    return 1;
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

sub rest_api($self, $req) {
    my $qf = \$req->query_form;
    my $endpoint = $req->path =~ m@/\w+$@;
    my $builder = Sonos::HTTP::MapBuilder->new($self->system(), $qf);

    my %dispatch = (
        "globals"=> sub { $builder->build_globals_data( $qf ) },
        "zones"  => sub { $builder->build_queue_data( $player ) },
        "music"  => sub { $builder->build_music_data( $qf ) },
        "active" => sub { $builder->build_zone_data( $player ) },
    );

    my $response = HTTP::Response->new( 200 );
    $response->add_content( "Hello, world!\n" );
    $response->content_type( "text/plain" );
    $response->content_length( length $response->content );
    $req->respond( $response );

    return 1;
}