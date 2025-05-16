package Sonos::Player::Queue;

use base 'Sonos::Player::Service';

use v5.36;
use strict;
use warnings;

require Sonos::MetaData;

sub contentDirectory($self) {
    return $self->player()->contentDirectory();
}

sub musicLibrary($self) {
    return $self->contentDir()->musicLibrary();
}

# Queue service has a different prefix
sub fullName($self) {
    return 'urn:schemas-sonos-com:service:Queue:1';
}

sub info($self) {
    my @queue = $self->items();

    my $separator = \' | ';

    if ( scalar @queue ) {
        use Text::Table ();
        my @headers = map { $separator, $_ } Sonos::MetaData::displayFields(), $separator;
        my $table   = Text::Table->new(@headers);
        $table->add( $_->displayValues() ) for @queue;

        $self->player()->log( "Queue:\n" . $table->table() );
    }
    else {
        $self->player()->log("Queue empty.");
    }
}

sub TO_JSON($self) {
    return {
        "last_update" => $self->lastUpdate(),
        "items"       => [ map { $_->TO_JSON() } $self->items() ]
    };
}

sub processUpdate {
    my $self = shift;

    my @items = $self->contentDirectory()->fetchByObjectID("Q:0");
    my %items = map { $_->{id} => Sonos::MetaData->new( $_, $self ) } @items;
    $self->{_items} = {%items};

    $self->SUPER::processUpdate(@_);
}

sub item( $self, $id ) {
    return $self->{_items}->{$id};
}

sub items($self) {
    my @items = values %{ $self->{_items} };
    @items = sort { $a->baseID() <=> $b->baseID() } @items;
    return @items;
}

1;
