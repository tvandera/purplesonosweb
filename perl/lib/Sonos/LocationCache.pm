package Sonos::LocationCache;

use v5.36;
use strict;
use warnings;

use JSON::XS    qw( decode_json encode_json );
use File::Slurp qw( read_file write_file );

use constant JSON_BASENAME => "location_cache.json";

sub new {
    my ($class) = @_;
    my $self = bless { _locations => {} }, $class;
    $self->load();
    return $self;
}

sub cacheFilename($self) {
    return JSON_BASENAME;
}

sub load($self) {
    my $filename = $self->cacheFilename();
    return if not -e $filename;
    $self->{_locations} = decode_json( read_file($filename) );
}

sub save($self) {
    write_file( $self->cacheFilename(), encode_json( $self->{_locations} ) );
}

sub locations($self) {
    return values %{ $self->{_locations} };
}

sub remove( $self, $location ) {
        my @uuids = grep { $self->{_locations}->{$_} eq $location }
            keys %{ $self->{_locations} };
        return unless @uuids;
        delete @{ $self->{_locations} }{@uuids};
        $self->save();
}

sub add( $self, $uuid, $location ) {
    return unless defined $location && length $location;
    return if defined $self->{_locations}->{$uuid}
      && $self->{_locations}->{$uuid} eq $location;
    $self->{_locations}->{$uuid} = $location;
    $self->save();
}

1;