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

    my $sockhost =
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

###############################################################################
sub handle_request($self, $server, $r) {
    $self->send_error($r, 501) unless $self->system() and $self->system()->populated();

    # No r, just return
    unless ( $r && $r->path ) {
        $self->log("Empty request");
        return;
    }

    my $path  = $r->path;
    my %qf   = $r->query_form;

    $self->log("handling request: ", $path);

    if (my $callback = $self->{_handlers}->{$path}) {
        $self->log("  handler: ", $path);
        &$callback($r);
        return;
    }


    if ( ( $path eq "/" ) || ( $path =~ /\.\./ ) ) {
        my $redirect = $self->defaultPage;
        $self->send_redirect($r, $redirect);
        return;
    }

    # Find where on disk
    my $diskpath = $self->diskpath($path);
    if ( ! -e $diskpath ) {
        $self->send_error($r, HTTP::Status::RC_NOT_FOUND);
        return;
    }

    # File is a directory, redirect for the browser
    if ( -d $diskpath ) {
        my $redirect = catfile($path, "index.html");
        $self->send_redirect($r, $redirect);
        return;
    }

    # File isn't HTML/XML/JSON/JS, just send it back raw
    if (  $path !~ /\.(html|xml|js|json)$/ )
    {
        $self->send_file_response($r, $diskpath);
        return;
    }

    if ( exists $qf{action} ) {
        $self->handle_zone_action( $r, $path ) if ( exists $qf{zone} );
        $self->handle_action( $r, $path );
    }

    my $tmplhook;
    $self->send_tmpl_response($r, $diskpath);
}

###############################################################################
sub handle_zone_action {
    my ($self, $r, $path ) = @_;

    my %qf = $r->query_form;
    my $mpath = decode( "UTF-8", $qf{mpath} );
    my $action = $qf{action};

    my $player = $self->player($qf{zone});
    my $rendering = $player->renderingControl();
    my $av = $player->avTransport();
    my $zones = $player->zoneGroupTopology();

    my %action_dispatch = (
        "Play"       => sub { $av->play() },
        "Pause"      => sub { $av->pause() },
        "Stop"       => sub { $av->stop() },

        "MuteOn"     => sub { $rendering->setMute(1); },
        "MuteOff"    => sub { $rendering->setMute(0); },

        "MuchSofter" => sub { $rendering->changeVolume(-5); },
        "Softer"     => sub { $rendering->changeVolume(-1); },
        "Louder"     => sub { $rendering->changeVolume(+1); },
        "MuchLouder" => sub { $rendering->changeVolume(+5); },
    );

    carp "Unknown action \"$action\"" unless exists $action_dispatch{$action};

    $action_dispatch{$action}->();

}

###############################################################################
sub handle_action {
    my ($self,  $r, $path ) = @_;
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
    my $uri = $r->path;
    my %qf = $r->query_form;
    my $mpath = $qf{mpath};
    my $item;
    if ($mpath =~ m/^Q:/) {
        # FIXME
        my $player = $self->player($qf{zone});
        $item = $player->contentDirectory()->queue()->get($mpath);
    } else {
        $item = $self->system()->musicLibrary()->item($mpath);
    }
    my ($mime_type, $blob) = $item->getAlbumArt();
    my $content_length = length $blob;
    my $response = HTTP::Response->new(200, undef, [
        "Content-Type" => $mime_type,
        "Content-Length" => $content_length,
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
}

sub send_redirect($self, $r, $to) {
    my $response = HTTP::Response->new(301, undef, ["Location" => $to,"Content-Length" => 0]);
    $r->respond( $response );
    $self->log("  redirect to $to");
}

sub send_error($self, $r, $code) {
    my $response = HTTP::Response->new($code, undef, ["Content-Length" => 0]);
    $r->respond( $response );
    $self->log("  error: $code");
}

sub send_hello($self, $req) {
    my $response = HTTP::Response->new( 200 );
    $response->add_content( "Hello, world!\n" );
    $response->content_type( "text/plain" );
    $response->content_length( length $response->content );
    $req->respond( $response );
}