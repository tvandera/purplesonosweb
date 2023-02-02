package Sonos::ContentCache;

use v5.36;
use strict;
use warnings;

require Sonos::ContentCache::Item;

use JSON;
use File::Slurp;
require URI::WithBase;
use Digest::SHA qw(sha256_hex);
use LWP::UserAgent;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;

use constant JSON_BASENAME => "content_cache.json";
use constant AA_BASENAME => "album_art";

# Contains music library cache
sub new {
    my($self, $name) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _name => $name,
        _updateids => { },
        _items => { },
        _album_art => {},
        _useragent => LWP::UserAgent->new(),
    }, $class;

    $self->load();

    return $self;
}

sub cacheFileName($self) {
    return $self->{_name} . "_" . JSON_BASENAME;
}

sub albumArtDir($self) {
    mkdir AA_BASENAME unless -f AA_BASENAME;
    return AA_BASENAME;
}

sub load($self) {
    my $filename = $self->cacheFileName();
    return if not -e $filename;
    my ($updateids, $items, $album_art) = @{decode_json(read_file($filename))};

    $self->{_updateids} = $updateids if defined $updateids;
    $self->addItemsOnly(@$items) if defined $items;

    for (values %$album_art) {
        # blob = readfile($sha)
        $filename = join "/", $self->albumArtDir(), $_->[0];
        $_->[2] = read_file($filename);
    }

    $self->{_album_art} = $album_art;
}

sub save($self) {
    my $filename = $self->cacheFileName();
    #unbless items
    my $allitems = [ map { $_->{_data} } values %{$self->{_items}} ];

    # save albumart w/o binary blobs
    my %artnoblobs = %{$self->{_album_art}};
    $_->[2] = undef for values %artnoblobs;

    write_file($filename, encode_json([
        $self->{_updateids},
        $allitems,
        \%artnoblobs,
    ]));
}

sub getVersion($self, $id) {
    my $value = $self->{_updateids}->{$id};
    return ("", -1) unless defined $value;
    return @$value;
}

sub getItems($self, $parentID) {
    my @items = values %{$self->{_items}};
    return grep { $_->parentID eq $parentID } @items;
}

sub getItem($self, $id) {
    return $self->{_items}->{$id};
}

# returns a JPEG/PNG/.. blob
# - cache key: albumArtURI
# - cache values: [ sha of blob, mime-type, blob ]
sub albumArtHelper($self, $uri, $baseurl) {
    # in cache?
    my $cache_ref = $self->{_album_art}->{$uri};
    if (defined $cache_ref) {
        my ($sha, $mime_type, $blob) = @$cache_ref;
        return $mime_type, $blob;
    }

    my $full_uri  = URI::WithBase->new($uri, $baseurl);
    DEBUG "Full uri: " . $full_uri->abs();
    my $response = $self->{_useragent}->get($full_uri->abs());
    carp "$uri not found" unless $response->is_success();

    my $mime_type = $response->content_type();
    my $blob = $response->content;
    my $sha = sha256_hex($blob);
    $self->{_album_art}->{$uri} = [ $sha, $mime_type, $blob ];
    $self->save();

    # also write blob if not yet written
    my $filename = join "/", $self->albumArtDir, $sha;
    write_file($filename, $blob) unless -e $filename;

    return $mime_type, $blob;
}

# only items, no cache id or version info
sub addItemsOnly($self, @items) {
    for (@items) {
        carp "No id: " . Dumper(\@items) unless defined $_->{id};
        $self->{_items}->{$_->{id}} = Sonos::ContentCache::Item->new($self, $_);
    }
}

sub addItems($self, $id, $udn, $version, @items) {
    $self->addItemsOnly(@items);
    $self->{_updateids}->{$id} = [ $udn, $version ];
    $self->save();
}

1;