package Sonos::AlbumArtCache;

use v5.36;
use strict;
use warnings;

require Sonos::MetaData;

use List::Util qw(first reduce);
use File::Slurp;
require URI::WithBase;
use Digest::SHA qw(sha256_hex);
use LWP::UserAgent;

use IO::Scalar;
require File::MimeInfo::Magic;
require File::MimeInfo;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;

use constant AA_BASENAME => "album_art";

# Contains music library cache
sub new {
    my($self, $discovery) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _discovery => $discovery,
        _album_art => {},
        _useragent => LWP::UserAgent->new(),
        _mime_types =>  MIME::Types->new,
    }, $class;

    return $self;
}

sub albumArtDir($self) {
    mkdir AA_BASENAME unless -f AA_BASENAME;
    return AA_BASENAME;
}

sub system($self) {
    return $self->{_discovery};
}

sub mimeTypeOf($self, $blob) {
    my $SH = IO::Scalar->new(\$blob);
    return File::MimeInfo::Magic::magic($SH);
}

sub extensionOf($self, $blob) {
    my $mime_type = $self->mimeTypeOf($blob);
    my @extensions = File::MimeInfo::extensions($mime_type);
    return shift @extensions;
}


# returns a JPEG/PNG/.. blob
# - cache key: albumArtURI
# - cache values: [ sha of blob, mime-type, blob ]
sub get($self, $uri) {

    # choose a random player to download from
    my @players = $self->system()->players();
    my $player = $players[rand @players];
    my $baseurl = $player->location();

    my $sha = sha256_hex($uri);
    my $filename;

    my $mime_type;
    my $blob;

    # in memory cache?
    my $cache_ref = $self->{_album_art}->{$sha};
    if (defined $cache_ref) {
        ($mime_type, $blob, $filename) = @$cache_ref;
    # in file cache?
    } elsif (my $full_filename = glob $self->albumArtDir() . "/" . $sha . ".*"){
        $blob = read_file($full_filename);
        $mime_type = $self->mimeTypeOf($full_filename);
        $filename = (split "/", $full_filename)[-1];
        $self->{_album_art}->{$sha} = [ $mime_type, $blob, $filename ];
    # no? -> download
    } else {
        my $full_uri  = URI::WithBase->new($uri, $baseurl);
        my $response = $self->{_useragent}->get($full_uri->abs());
        carp "$uri not found" unless $response->is_success();

        $blob = $response->content;
        # Sonos returns the wrong or no mime type, determine from blob
        $mime_type = $self->mimeTypeOf($blob);
        $filename = $sha . "." . $self->extensionOf($blob);
        $self->{_album_art}->{$sha} = [ $mime_type, $blob, $filename ];

        # also write blob to file cache
        write_file($self->albumArtDir() . "/" . $filename, $blob);
    }

    return $sha, $mime_type, $blob, $filename;
}

1;