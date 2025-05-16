package Sonos::AlbumArtCache;

use v5.36;
use strict;
use warnings;

require Sonos::MetaData;

use Try::Tiny qw( catch try );
use JSON::XS qw( decode_json encode_json );
use File::Slurp qw( read_file write_file );
use URI::WithBase ();
use Digest::SHA qw( sha256_hex );
use LWP::UserAgent ();

use IO::Scalar;
use File::MimeInfo::Magic ();
use File::MimeInfo ();

use Image::Resize ();

use constant AA_BASENAME => "albumart_cache";
use constant JSON_BASENAME => "albumart_cache.json";

# Contains music library cache
sub new {
    my($self, $system) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _system => $system,
        _album_art => {},
        _useragent => LWP::UserAgent->new(),
    }, $class;

    $self->load();

    return $self;
}

sub cacheDir($self) {
    mkdir AA_BASENAME unless -f AA_BASENAME;
    return AA_BASENAME;
}

sub cacheFilename($self) {
    return JSON_BASENAME;
}

sub load($self) {
    my $cachefilename = $self->cacheFilename();
    return if not -e $cachefilename;

    my @items = @{decode_json(read_file($cachefilename))};

    for (@items) {
        my ($sha, $mime_type, $filename) = @$_;
        my $blob;

        $blob = read_file($self->cacheDir() . "/" . $filename) if $filename;
        $self->{_album_art}->{$sha} = [ $mime_type, $blob, $filename ];
    }
}

sub save($self) {
    my $filename = $self->cacheFilename();

    # items w/o blob
    my @items = ();
    for my $sha (keys %{$self->{_album_art}}) {
        my ( $mime_type, $blob, $filename) = @{$self->{_album_art}->{$sha}};
        push @items, [ $sha, $mime_type, $filename ]
    }

    write_file($filename, encode_json(\@items));
}

sub system($self) {
    return $self->{_system};
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

sub resize($self, $blob) {
    my $gdinput = GD::Image->new($blob);
    my $image = Image::Resize->new($gdinput);
    my $gdoutput = $image->resize(200, 200);
    return $gdoutput->jpeg();
}


# returns a JPEG/PNG/.. blob
# - cache key: albumArtURI
# - cache values: [ sha of blob, mime-type, blob ]
sub get($self, $uri) {
    my $sha = sha256_hex($uri);

    # in memory cache?
    my $cache_ref = $self->{_album_art}->{$sha};
    if (defined $cache_ref) {
        $self->system()->log("aacache", "hit [$uri]");
        return $sha, @$cache_ref;
    }

    # choose a random player to download from
    my @players = $self->system()->players();
    my $player = $players[rand @players];
    my $baseurl = $player->location();
    my $full_uri  = URI::WithBase->new($uri, $baseurl);

    my ($mime_type, $blob, $filename) = (undef, undef, undef);

    try {
        my $response = $self->{_useragent}->get($full_uri->abs());
        if ($response->is_success()) {
            $blob = $response->content;
            $blob = $self->resize($blob);

            # Sonos returns the wrong or no mime type, determine from blob
            $mime_type = $self->mimeTypeOf($blob);
            $filename = sha256_hex($blob) . "." . $self->extensionOf($blob);

            # also write blob to file cache
            my $full_filename = $self->cacheDir() . "/" . $filename;
            write_file($full_filename, $blob) unless -e $full_filename;
        }
    } catch {
        $self->system()->log("aacache", "failed [$uri]: $_");
    };

    # save + write json
    $self->{_album_art}->{$sha} = [ $mime_type, $blob, $filename ];
    $self->save();

    $self->system()->log("aacache", "miss [$uri]");

    return $sha, $mime_type, $blob, $filename;
}

1;