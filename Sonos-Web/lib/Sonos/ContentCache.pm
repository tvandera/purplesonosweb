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

use constant CACHE => "content_cache.json";

# Contains music library cache
sub new {
    my($self, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _updateids => { },
        _items => { },
    }, $class;

    $self->load(CACHE);

    return $self;
}

sub DESTROY($self) {
    $self->save(CACHE);
}

sub load($self, $filename) {
    return if not -e $filename;
    my ($updateids, $items) = @{decode_json(read_file($filename))};
    $self->{_updateids} = $updateids if defined $updateids;
    $self->{_items} = $items if defined $items;
}

sub save($self, $filename) {
    write_file($filename, encode_json([ $self->{_updateids}, $self->{_items} ]));
}

sub getUpdateID($self, $id) {
    my $value = $self->{_updateids}->{$id};
    return "" unless defined $value;
    return $value;
}

sub mergeUpdateIDs($self, %ids) {
     # merge new UpdateIDs into existing ones
    %{$self->{_updateids}} = ( %{$self->{_updateids}}, %ids);
}

sub getItem($self, $id) {
    return $self->{_items}->{$id};
}

sub addItems($self, @items) {
    for (@items) {
        $self->{_items}->{$_->{id}} = $_;
    }
}

1;