package Sonos::Player::ContentDirectory;

use v5.36;
use strict;
use warnings;

use base 'Sonos::Player::Service';

require Sonos::MetaData;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use Data::Dumper;
use Carp;

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

sub new {
   my ($class, @args) = @_;

    # possibly call Parent->new(@args) first
    my $self = $class->SUPER::new(@args);

    my $udn = $self->getPlayer()->UDN();
    $self->{_contentcache} = Sonos::ContentCache->new($udn);

    return $self;
}

sub queue($self) {
    my @items = $self->localCache()->getItems("Q:0");
    return sort { $a->baseID() <=> $b->baseID() } @items;
}

sub info($self) {
    $self->logQueue();
}

sub logQueue($self) {
    my @queue = $self->queue();

    for (@queue) {
        $_->getAlbumArt($self->baseURL());
    }

    if (scalar @queue) {
        use Text::Table;
        my $table = Text::Table->new(Sonos::MetaData::displayFields());
        $table->add($_->displayValues()) for @queue;

        $self->getPlayer()->log("Queue:\n" . $table->table());
    } else {
        $self->getPlayer()->log("Queue empty.");
    }
}

# called when anything in ContentDirectory has been updated
# i.e.:
#  'SavedQueuesUpdateID' => 'RINCON_000E583472BC01400,12',
#  'ContainerUpdateIDs' => 'Q:0,503', <--- Queue is local per player!
#  'RadioFavoritesUpdateID' => 'RINCON_000E583472BC01400,97',
#  'SystemUpdateID' => '131',
#  'FavoritePresetsUpdateID' => 'RINCON_000E583472BC01400,97',
#  'FavoritesUpdateID' => 'RINCON_000E583472BC01400,98',
#  'RadioLocationUpdateID' => 'RINCON_000E585187D201400,347',
#  'ShareListUpdateID' => 'RINCON_000E585187D201400,206'
sub processUpdateIDs ( $self, $service, %properties ) {
    # check if anything was updated
    foreach my $key (keys %properties) {
        next if ($key !~ /UpdateIDs?$/);

        my $newvalue = $properties{$key};
        my ($new_location, $new_version) = split /,/, $newvalue;
        next unless defined $new_location;
        next unless defined $new_version;


        # if the UpdateID starts with RINCON_ data is global
        #    e.g. 'RadioFavoritesUpdateID' => 'RINCON_000E583472BC01400,97',
        # otherwise local to the player (player's queue)
        #    e.g. 'ContainerUpdateIDs' => 'Q:0,503',
        my $globalcache = $newvalue =~ m/^RINCON_/g;
        my $cache = $globalcache ? $self->globalCache() : $self->localCache();

        my ($existing_location, $existing_version) = $cache->getVersion($key);

        # INFO "Update ID $key: old $existing_location,$existing_version ?= new $newvalue";

        # call fetch if updated or not in cache
        if (not $existing_location or $existing_version < $new_version) {
            my @items = $self->fetchByUpdateID($key);
            $cache->addItems($key, $new_location, $new_version, @items);
        }
    }
}

sub processUpdate {
    my $self = shift;

    $self->processUpdateIDs(@_);
    $self->SUPER::processUpdate(@_);

    $self->logQueue();

}


# finds items in rootItems that have updateid equal to given $updateid and
# fetches those
sub fetchByUpdateID {
    my ($self, $updateid)  = @_;
    my @matching = grep { $_->{update_id} eq $updateid } Sonos::MetaData::rootItems();
    my @items = map { $self->fetchByObjectId($_->{id}) } @matching;
    return @items
}


###############################################################################
# objectid is like :
# - AI: for audio-in
# - Q:0 for queue
#
# actiontype is
#  - "BrowseMetadata", or
#  - "BrowseDirectChildren" (default)
sub fetchByObjectId( $self, $objectid, $recurse = 0) {
    my $start = 0;
    my @items  = ();
    my $result;

    $self->getPlayer()->log("Fetching " . $objectid . "...");

    do {
        $result = $self->controlProxy()->Browse( $objectid, 'BrowseDirectChildren', 'dc:title,res,dc:creator,upnp:artist,upnp:album', $start, 2000, "" );

        return () unless $result->isSuccessful;

        $start += $result->getValue("NumberReturned");

        my $results = $result->getValue("Result");
        my $tree    = XMLin(
            $results,
            forcearray => [ "item", "container" ],
            keyattr    => {}
        );

        push( @items, @{ $tree->{item} } ) if ( defined $tree->{item} );
        push( @items, @{ $tree->{container} } ) if ( defined $tree->{container} );
    } while ( $start < $result->getValue("TotalMatches") );

    @items = map { Sonos::Player::Service::derefHelper($_) }  @items;

    $self->getPlayer()->log(" .  Found " . scalar(@items) . " entries.");
    #DEBUG Dumper(@items[0..10]);

    return @items unless $recurse;

    # recursively add sub-containers
    my @subitems = ();
    for (@items) {
        next unless $_->{"upnp:class"} =~ /container/;
        push @subitems, $self->fetchByObjectId($_->{id});
    }

    return @items, @subitems;
}

sub localCache($self) {
    return $self->{_contentcache};
}

sub globalCache($self) {
    return $self->{_player}->{_discovery}->{_contentcache};
}

###############################################################################
sub addRadioStation($self, $name, $station_url) {
    $station_url = substr( $station_url, 5 ) if ( substr( $station_url, 0, 5 ) eq "http:" );
    $name    = enc($name);

    my $item =
        '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" '
      . 'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
      . 'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
      . '<item id="" restricted="false"><dc:title>'
      . $name
      . '</dc:title><res>x-rincon-mp3radio:'
      . $station_url
      . '</res></item></DIDL-Lite>';

    return $self->createObject( "R:0/0", $item );
}

# add a radio station or play list
sub createObject( $self, $containerid, $elements ) {
    return  $self->contentDirProxy->CreateObject( $containerid, $elements );
}

# remove a radio station or play list
sub destroyObject( $self, $objectid ) {
    $self->contentDirProxy()->DestroyObject($objectid);
}

###############################################################################

sub refreshShareIndex($self) {
    return if $self->{_updateids}->{ShareIndexInProgress};
    $self->contentDirProxy()->RefreshShareIndex();
}

1;