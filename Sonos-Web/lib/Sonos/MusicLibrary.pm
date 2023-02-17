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

    $self->load();
    $self->addTopItems();

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

sub playerForID($self, $id) {
    # find the longest root id thats starts with $id
    # e.g. A:ALBUM for $id = A:ALBUM/SomeAlbumName
    my @rootids = map { $_->{id} } Sonos::MetaData::topItems();
       @rootids = grep { rindex($id, $_, 0) == 0 } @rootids;
    my $rootid = reduce { length($a) > length($b) ? $a : $b } @rootids;

    return undef unless $rootid;

    my ($uuid, $version) = @{$self->{_updateids}->{$rootid}};
    my $player = $self->discovery()->player($uuid);
    return $player
}

sub fetchChildren($self, $parentID) {
    # already fetched
    return if defined $self->{_tree}->{$parentID};

    my $player = $self->playerForID($parentID);

    my @items = $player->contentDirectory()->fetchByObjectID($parentID);
    $self->addItemsOnly(@items);

    return @items;
}

sub hasChildren($self, $parentid) {
    my $childref = $self->{_tree}->{$parentid};
    return (defined $childref and @$childref);
}

sub children($self, $parent) {
    return () unless $parent->isContainer();
    my $parentid = $parent->id();

    $self->fetchChildren($parentid);

    my @ids = @{$self->{_tree}->{$parentid}};
    my @items = map { $self->{_items}->{$_} } @ids;
    @items = sort { $a->title() cmp $b->title() } @items;
    return @items;
}

sub item($self, $id) {
    # root item can be "/" or ""
    $id = "" if $id eq "/";
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
    # sort by $id, such that parent is added before children
    @items = sort { $a->{id} cmp $b->{id} } @items;
    for (@items) {
        my $id = $_->{id};
        my $parentid = $_->{parentID};

        my $item;
        if (exists $self->{_items}->{$id}) {
            $item = $self->{_items}->{$id};
        } else {
            $item = $self->{_items}->{$id} = Sonos::MetaData->new($_, $self);

            # mark this item as a container with unknown content
            $self->{_tree}->{$id} = undef if item->isContainer();
        }

        next if $item->isRootItem();

        carp "Parent item with id $parentid does not exist"
            unless exists $self->{_items}->{$parentid};

        carp "Parent id $parentid not lexographically before child $id"
            unless $parentid lt $id;

        $self->{_tree}->{$parentid} = [] unless defined $self->{_tree}->{$parentid};
        my $itemlist = $self->{_tree}->{$parentid};
        carp "Item with id $id already exists in parent list" if grep{$_ eq $id} @$itemlist;

        push @$itemlist, $id;
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

sub addTopItems($self) {
    return if $self->hasChildren("");
    $self->addItemsOnly(Sonos::MetaData::topItems());
}

sub removeChildren($self, $id) {
    return unless ($self->hasChildren($id));
    my @childids = @{$self->{_tree}->{$id}};
    $self->remove($_) for @childids;
}

sub remove($self, $id) {
    $self->removeChildren($id);
    delete $self->{_tree}->{$id};
    delete $self->{_items}->{$id};
}

1;