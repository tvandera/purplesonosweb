package Sonos::Player::Queue;

use v5.36;
use strict;
use warnings;

require Sonos::MetaData;

use List::Util qw(first);
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
    my($self, $contentdir) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _contentdir => $contentdir,
        _version => -1,
        _items => []
    }, $class;

    return $self;
}

sub contentDir($self) {
    return $self->{_contentdir};
}

sub player($self) {
    return $self->contentDir()->player();
}

sub info($self) {
    my @queue = $self->items();

    my $separator =  \' | ';

    if (scalar @queue) {
        use Text::Table;
        my @headers = map { $separator, $_ } Sonos::MetaData::displayFields(), $separator;
        my $table = Text::Table->new(@headers);
        $table->add($_->displayValues()) for @queue;

        $self->player()->log("Queue:\n" . $table->table());
    } else {
        $self->player()->log("Queue empty.");
    }
}


sub version($self) {
    return $self->{_version};
}

sub get($self, $id) {
    return $self->{_items}->[$id];
}

sub items($self) {
    return @{$self->{_items}};
}

sub update($self, $version, @items) {
    $self->{_version} = $version;

    @items = map { Sonos::MetaData->new($_, $self) } @items;
    @items = sort { $a->baseID() <=> $b->baseID() } @items;
    $self->{_items} = [ @items ];
}

# forward albumArtHelper to music library
# to allow global caching
sub albumArtHelper {
    my $self = shift;
    return $self->{_musiclib}->albumArtHelper(@_);
}

1;