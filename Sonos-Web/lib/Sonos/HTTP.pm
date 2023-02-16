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

sub getSystem($self) {
    return $self->{_discovery};
}

sub player($self, $name_or_uuid) {
    return $self->getSystem()->player($name_or_uuid);
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
    my $player = $self->player($qf{zone});
    my $action = $qf{action};


    # AVtransport Actions
    my $av = $player->avTransport();
    my @av_actions = ( "Play", "Pause", "Stop", "ShuffleOn", "ShuffleOff", "RepeatOn", "RepeatOff");
    $av->$action() if grep /^$action$/, @av_actions;


#         "Seek" ) {
#         "Remove" => sub { $player->removeTrack( $qf{queue} ); return 4; },
#         "RemoveAll" => sub { $player->removeAll() return 4; },

#     my %action_table (
#         # ContentDirectory actions
#

#
#         # Render actions
#  "MuteOn" ) {
# "MuteOff" ) {
#  "MuchSofter" ) {
#    "Softer" ) {
#  "Louder" ) {
#    "MuchLouder" ) {
#    "SetVolume" ) {
#     elsif ( $qf{action} eq "Save" ) {
#         upnp_avtransport_save( $zone, $qf{savename} );
#         return 0;
#     }
#     elsif ( $qf{action} eq "AddMusic" ) {
#         my $class = sonos_music_class($mpath);
#         if ( sonos_is_radio($mpath) ) {
#             sonos_avtransport_set_radio( $zone, $mpath );
#             return 2;
#         }
#         elsif ( $class eq "object.item.audioItem" ) {
#             sonos_avtransport_set_linein( $zone, $mpath );
#             return 2;
#         }
#         else {
#             sonos_avtransport_add( $zone, $mpath );
#             return 4;
#         }
#     }
#     elsif ( $qf{action} eq "DeleteMusic" ) {
#         if ( sonos_music_class($mpath) eq "object.container.playlist" ) {
#             my $entry = sonos_music_entry($mpath);
#             upnp_content_dir_delete( $zone, $entry->{id} );
#         }
#         return 0;
#     }
#     elsif ( $qf{action} eq "PlayMusic" ) {
#         my $class = sonos_music_class($mpath);
#         if ( sonos_is_radio($mpath) ) {
#             sonos_avtransport_set_radio( $zone, $mpath );
#         }
#         elsif ( $class eq "object.item.audioItem" ) {
#             sonos_avtransport_set_linein( $zone, $mpath );
#         }
#         else {
#             if ( !( $main::ZONES{$zone}->{AV}->{AVTransportURI} =~ /queue/ ) ) {
#                 sonos_avtransport_set_queue($zone);
#             }
#             upnp_avtransport_action( $zone, "RemoveAllTracksFromQueue" );
#             sonos_avtransport_add( $zone, $mpath );
#             upnp_avtransport_play($zone);
#         }
#
#         return 4;
#     }
#     elsif ( $qf{action} eq "LinkAll" ) {
#         sonos_link_all_zones($zone);
#         return 2;
#     }
#     elsif ( $qf{action} eq "Unlink" ) {
#         sonos_unlink_zone( $qf{link} );
#         return 2;
#     }
#     elsif ( $qf{action} eq "Link" ) {
#         sonos_link_zone( $zone, $qf{link} );
#     }
#     else {
#         return 0;
#     }
    return 1;
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
        return ( $self->getSystem()->lastUpdate() > $qf{lastupdate} ) ? 1 : 5;
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
    my $template = Sonos::HTTP::Template->new($self->getSystem(), $diskpath, \%qf);
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

        my $player = $self->player($qf{zone});
        $item = $player->contentDirectory()->queue()->get($mpath);
    } else {
        $item = $self->getSystem()->musicLibrary()->getItem($mpath);
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