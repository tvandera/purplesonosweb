package Sonos::ContentCache;

use v5.36;
use strict;
use warnings;

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

sub DESTROY($self) {
    $self->save();
}

sub load($self) {
    my $filename = $self->cacheFileName();
    return if not -e $filename;
    my ($updateids, $items) = @{decode_json(read_file($filename))};
    $self->{_updateids} = $updateids if defined $updateids;
    $self->{_items} = $items if defined $items;
}

sub save($self) {
    my $filename = $self->cacheFileName();
    write_file($filename, encode_json([ $self->{_updateids}, $self->{_items} ]));
}

sub getUpdateID($self, $id) {
    my $value = $self->{_updateids}->{$id};
    return "" unless defined $value;
    return $value;
}

sub getItem($self, $id) {
    return $self->{_items}->{$id};
}

sub addItems($self, $id, $value, @items) {
    for (@items) {
        $self->{_items}->{$_->{id}} = $_;
    }
    $self->{_updateids}->{$id} = $value;
}

1;