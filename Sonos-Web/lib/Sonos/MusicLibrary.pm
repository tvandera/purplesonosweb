package Sonos::MusicLibrary;

use v5.36;
use strict;
use warnings;

require Sonos::MetaData;

use List::Util qw(first reduce);
use JSON::XS;
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
    my($self, $discovery) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _discovery => $discovery,
        _updateids => { },
        _items => { },
        _tree => { },
        _album_art => {},
        _useragent => LWP::UserAgent->new(),
    }, $class;

    $self->addRootItems();
    $self->load();

    return $self;
}

sub cacheFileName($self) {
    return JSON_BASENAME;
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

sub version($self, $id) {
    my $value = $self->{_updateids}->{$id};
    return ("", -1) unless defined $value;
    return @$value;
}

sub discovery($self) {
    return $self->{_discovery};
}

sub hasItems($self, $parentID) {
    return exists $self->{_tree}->{$parentID};
}

sub playerForID($self, $id) {
    # find the longest root id thats starts with $id
    # e.g. A:ALBUM for $id = A:ALBUM/SomeAlbumName
    my @rootids = map { $_->{id} } Sonos::MetaData::rootItems();
       @rootids = grep { rindex($id, $_, 0) == 0 } @rootids;
    my $rootid = reduce { length($a) > length($b) ? $a : $b } @rootids;

    return undef unless $rootid;

    my ($uuid, $version) = @{$self->{_updateids}->{$rootid}};
    my $player = $self->discovery()->player($uuid);
    return $player
}

sub fetchItems($self, $parentID) {
    my $player = $self->playerForID($parentID);

    my @items = $player->contentDirectory()->fetchByObjectID($parentID);
    $self->addItemsOnly(@items);

    return @items;
}

sub getChildIDs($self, $parentID) {
    $self->fetchItems($parentID) unless $self->hasItems($parentID);
    return @{$self->{_tree}->{$parentID}};
}


sub getChildren($self, $parent) {
    return () unless $parent->isContainer();
    my @ids = $self->getChildIDs($parent->id());
    return map { $self->{_items}->{$_} } @ids;
}

sub getItem($self, $id) {
    return $self->{_items}->{$id};
}

# returns a JPEG/PNG/.. blob
# - cache key: albumArtURI
# - cache values: [ sha of blob, mime-type, blob ]
sub albumArtHelper($self, $item, $player) {
    $player = $self->playerForID($item->id()) unless $player;

    my $uri = $item->albumArtURI();
    my $baseurl = $player->location();

    # in cache?
    my $cache_ref = $self->{_album_art}->{$uri};
    if (defined $cache_ref) {
        my ($sha, $mime_type, $blob) = @$cache_ref;
        return $mime_type, $blob;
    }

    my $full_uri  = URI::WithBase->new($uri, $baseurl);
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
        $self->{_items}->{$_->{id}} = Sonos::MetaData->new($_, $self);
        push @{$self->{_tree}->{$_->{parentID}}}, $_->{id};
    }
}

sub addItems($self, $id, $udn, $version, @items) {
    $self->addItemsOnly(@items);
    $self->{_updateids}->{$id} = [ $udn, $version ];
    $self->save();
}

sub player($self, $id) {
    my ($udn, $version) = $self->{_updateids}->{$id};
    $self->{_discovery}->player($udn);
}

sub addRootItems($self) {
    $self->addItemsOnly(Sonos::MetaData::rootItems());
}

sub removeItems($self, $parentID) {
    if ($self->hasItems($parentID)) {
        my @ids = $self->getChildIDs($parentID);
        $self->removeItems($_) for @ids;
    }
    delete $self->{_tree}->{$parentID};
    delete $self->{_items}->{$parentID};
}

1;