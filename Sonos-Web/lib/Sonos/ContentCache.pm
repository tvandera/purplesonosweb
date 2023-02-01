package Sonos::ContentCache;

use v5.36;
use strict;
use warnings;

require Sonos::ContentCache::Item;

use JSON;
use File::Slurp;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;

use constant BASENAME => "content_cache.json";

# Contains music library cache
sub new {
    my($self, $name) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _name => $name,
        _updateids => { },
        _items => { },
    }, $class;

    $self->load();

    return $self;
}

sub cacheFileName($self) {
    return $self->{_name} . "_" . BASENAME;
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
    write_file($filename, encode_json([ $self->{_updateids}, $allitems ]));
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

# only items, no cache id or version info
sub addItemsOnly($self, @items) {
    for (@items) {
        carp "No id: " . Dumper(\@items) unless defined $_->{id};
        $self->{_items}->{$_->{id}} = Sonos::ContentCache::Item->new($_);
    }
}

sub addItems($self, $id, $udn, $version, @items) {
    $self->addItemsOnly(@items);
    $self->{_updateids}->{$id} = [ $udn, $version ];
    $self->save();
}

1;