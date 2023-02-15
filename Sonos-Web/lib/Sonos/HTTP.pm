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
        _daemon => HTTP::Daemon->new(ReuseAddr => 1, ReusePort => 1, %args),
        _handlers => {},
        _loop => $loop,
        _default_page => ($args{DefaultPage} || "index.html"),
        _mime_types =>  MIME::Types->new,
    }, $class;


    # HTTP Handlers
    $self->register_handler("/getaa", sub { $self->albumart_request(@_) });
    $self->register_handler("/getAA", sub { $self->albumart_request(@_) });

    # IO::Async
    my $handle = IO::Async::Listener->new(
         handle => $self->{_daemon},
         on_accept => sub { $self->handle_request(@_); }
    );

    $loop->add( $handle );

    print STDERR "Listening on " . $self->{_daemon}->url . "\n";

    return $self;
}

sub version($self) {
    return "0.99";
}

sub getSystem($self) {
    return $self->{_discovery};
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
sub handle_request($self, $handle, $c) {
    $c->blocking(1);
    my $r = $c->get_request;

    # No r, just return
    unless ( $r && $r->uri ) {
        $self->log("Empty request - reason: " . $c->reason());
        return;
    }

    my $uri  = $r->uri;
    $self->log("handling request: ", $uri);

    my %qf   = $uri->query_form;
    my $path = $uri->path;


    if (my $callback = $self->{_handlers}->{$path}) {
        $self->log("  handler: ", $path);
        &$callback($c, $r);
        return;
    }


    if ( ( $path eq "/" ) || ( $path =~ /\.\./ ) ) {
        my $redirect = $self->defaultPage;
        $c->send_redirect($redirect);
        $self->log("  redirect: ", $redirect);
        $c->force_last_request;
        $c->close;
        return;
    }

    # Find where on disk
    my $diskpath = $self->diskpath($path);
    if ( ! -e $diskpath ) {
        $c->send_error(HTTP::Status::RC_NOT_FOUND);
        $self->log("  not found");
        $c->force_last_request;
        $c->close;
        return;
    }

    # File is a directory, redirect for the browser
    if ( -d $diskpath ) {
        my $redirect = catfile($path, "index.html");
        $c->send_redirect($redirect);
        $self->log("  redirect: ", $redirect);
        $c->force_last_request;
        $c->close;
        return;
    }

    # File isn't HTML/XML/JSON/JS, just send it back raw
    if (  $path !~ /\.(html|xml|js|json)$/ )
    {
        $c->send_file_response($diskpath);
        $self->log("  raw");
        $c->force_last_request;
        return;
    }

    my $handled = 1;
    if ( exists $qf{action} ) {
        $handled = $self->handle_zone_action( $c, $r, $path ) if ( exists $qf{zone} );
        $handled ||= $self->handle_action( $c, $r, $path );
    }
    $handled = 1 if ( $qf{NoWait} );

    my $tmplhook;
    my @common_args = ( "*", \& send_tmpl_response, $c, $r, $diskpath, $tmplhook );
    $self->send_tmpl_response(@common_args);
    $self->log("  template");
}

###############################################################################
sub handle_zone_action {
    my ($self, $c, $r, $path ) = @_;
    my %qf = $r->uri->query_form;
    my $mpath = decode( "UTF-8", $qf{mpath} );
    my $player = $self->zonePlayer($qf{zone});

#     my %action_table (
#         # ContentDirectory actions
#
#         # AVtransport Actions
#         "Play" => sub {$player->avTran}
#    "Pause" ) {
#     "Stop" ) {
# "ShuffleOn" ) {
# q "ShuffleOff" ) {
#  "RepeatOn" ) {
# "RepeatOff" ) {
#
#         "Seek" ) {
#         "Remove" => sub { $player->removeTrack( $qf{queue} ); return 4; },
#         "RemoveAll" => sub { $player->removeAll() return 4; },
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
    my ($self,  $c, $r, $path ) = @_;
    my %qf = $r->uri->query_form;


    if ( $qf{action} eq "ReIndex" ) {
        sonos_reindex();
    }
    elsif ( $qf{action} eq "Unlink" ) {
        sonos_unlink_zone( $qf{link} );
    }
    elsif ( $qf{action} eq "Wait" && $qf{lastupdate} ) {
        return ( $self->lastUpdate() > $qf{lastupdate} ) ? 1 : 5;
    }
    else {
        return 0;
    }
    return 1;
}


###############################################################################
sub send_tmpl_response {
    my ($self,  $what, $zone, $c, $r, $diskpath, $tmplhook ) = @_;

    my %qf = $r->uri->query_form;

    # One of our templates, now fill in the parts we know
    my $template = Sonos::HTTP::Template->new($self->getSystem(), $diskpath, \%qf);
    my $content_type = $self->mimeTypeOf($diskpath);
    my $output = encode( 'utf8', $template->output );
    my $handled = HTTP::Response->new(
        200, undef,
        [
            Connection         => "close",
            "Content-Type"     => $content_type,
            "Pragma"           => "no-cache",
            "Cache-Control"    => "no-store, no-cache, must-revalidate, post-check=0, pre-check=0"
        ],
        $output
    );
    $c->send_response($handled);
    $c->force_last_request;
    $c->close;
}

sub albumart_request($self, $c, $r) {
    my $uri = $r->uri;
    my %qf = $uri->query_form;
    my $mpath = $qf{mpath};
    my $item;
    if ($mpath =~ m/^Q:/) {

        my $player = $self->zonePlayer($qf{zone});
        $item = $player->contentDirectory()->queue()->get($mpath);
    } else {
        $item = $self->getSystem()->musicLibrary()->getItem($mpath);
    }
    my ($mime_type, $blob) = $item->getAlbumArt();
    my $response = HTTP::Response->new(200, undef, ["Content-Type" => $mime_type], $blob);
    $c->send_response($response);
    $c->force_last_request;
}
