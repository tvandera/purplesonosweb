package Sonos::Player::ContentCache;

use v5.36;
use strict;
use warnings;

use JSON;
use File::Slurp;

use constant CACHE => "content_cache.json";

# Contains music library cache
sub new {
    my($self, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _updateids => { },
        _items => { },
    }, $class;

    $self->tryLoad(CACHE);

    return $self;
}

sub DESTROY($self) {
    $self->save(CACHE);
}

sub load($self, $filename) {
    my ($updateids, $items) = @{decode_json(read_file($filename))};
    $self->{_updateids} = $updateids if defined $updateids;
    $self->{_items} = $items if defined $items;
}

sub save($self, $filename) {
    write_file(encode_json([ $self->{_updateids}, $self->{_items} ]));
}

sub getUpdateId($self, $id) {
    return $self->{_updateids}->{$id};
}

sub getItem($self, $id) {
    return $self->{_items}->{$id};
}

sub addItem($self, @items) {
    for (@items) {
        $self->{_items}->{$_->{id}} = $_;
    }
}

1;