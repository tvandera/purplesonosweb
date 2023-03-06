package Sonos::MusicLibrary;

use v5.36;
use strict;
use warnings;

require Sonos::MetaData;

use List::Util qw(first reduce);
use JSON::XS;
use File::Slurp;



use constant JSON_BASENAME => "content_cache.json";

# Contains music library cache
sub new {
    my($self, $system) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _system => $system,
        _updateids => { },
        _items => { },
        _tree => { },
    }, $class;

    $self->load();
    $self->addTopItems();

    return $self;
}

sub cacheFileName($self) {
    return JSON_BASENAME;
}

sub load($self) {
    my $filename = $self->cacheFileName();
    return if not -e $filename;
    my ($updateids, $items) = @{decode_json(read_file($filename))};

    $self->{_updateids} = $updateids if defined $updateids;
    $self->addItemsOnly(@$items) if defined $items;
}

sub save($self) {
    my $filename = $self->cacheFileName();
    #unbless items
    my $allitems = [ map { $_->{_data} } values %{$self->{_items}} ];

    write_file($filename, encode_json([
        $self->{_updateids},
        $allitems,
    ]));
}

sub version($self, $id) {
    my $value = $self->{_updateids}->{$id};
    return ("", -1) unless defined $value;
    return @$value;
}

sub system($self) {
    return $self->{_system};
}

sub playerForID($self, $id) {
    # find the longest root id thats starts with $id
    # e.g. A:ALBUM for $id = A:ALBUM/SomeAlbumName
    my @rootids = map { $_->{id} } Sonos::MetaData::topItems();
       @rootids = grep { rindex($id, $_, 0) == 0 } @rootids;
    my $rootid = reduce { length($a) > length($b) ? $a : $b } @rootids;

    return unless $rootid;

    # now find what player to contact based on _updateids
    my ($uuid, $version) = @{$self->{_updateids}->{$rootid}};
    my $player = $self->system()->player($uuid);
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

sub topItem($self) {
    return $self->item("");
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
            # by putting it into _tree, with value undef
            $self->{_tree}->{$id} = undef if $item->isContainer();
        }

        next if $item->isRootItem();

        warn "Parent item with id $parentid does not exist"
            unless exists $self->{_items}->{$parentid};

        warn "Parent id $parentid not lexographically before child $id"
            unless $parentid lt $id;

        $self->{_tree}->{$parentid} = [] unless defined $self->{_tree}->{$parentid};
        my $itemlist = $self->{_tree}->{$parentid};
        warn "Item with id $id already exists in parent list" if grep{$_ eq $id} @$itemlist;

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
    $self->{_system}->player($udn);
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