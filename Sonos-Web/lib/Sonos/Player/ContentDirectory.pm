package Sonos::Player::ContentDirectory;

use v5.36;
use strict;
use warnings;

use base 'Sonos::Player::Service';

require Sonos::MetaData;
require Sonos::Player::Queue;



use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');


sub info($self) {
    $self->log($self->shortName, ":");
    my $top = $self->musicLibrary()->topItem();
    my @containers = $self->musicLibrary()->children($top);
    for (@containers) {
      my $num = scalar $self->musicLibrary->children($_);
      my $name = $_->title();
      $self->log("  $name: $num items");
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
    my $music = $self->musicLibrary();

    # check if anything was updated
    foreach my $update_id (keys %properties) {
        next if ($update_id !~ /UpdateIDs?$/);

        my $newvalue = $properties{$update_id};
        my ($new_location, $new_version) = split /,/, $newvalue;
        next unless defined $new_location;
        next unless defined $new_version;
        next unless $new_location =~ /RINCON_/;

        for (Sonos::MetaData::topItems()) {
            # find items in topItems that have updateid equal to given $updateid and
            # fetch those
            next unless $_->{update_id} eq $update_id;

            my $id = $_->{id};

            my ($existing_location, $existing_version) = $music->version($id);

            # call fetch if updated or not in music
            next if $existing_location and $existing_version >= $new_version;

            $music->removeChildren($id);
            my @items = $self->fetchByObjectID($id);

            $music->addItems($id, $new_location, $new_version, @items);
        }
    }
}

sub processUpdate {
    my $self = shift;

    $self->processUpdateIDs(@_);
    $self->SUPER::processUpdate(@_);

}




###############################################################################
# objectid is like :
# - AI: for audio-in
# - Q:0 for queue
#
# actiontype is
#  - "BrowseMetadata", or
#  - "BrowseDirectChildren" (default)
sub fetchByObjectID( $self, $objectid, $recurse = 0) {
    my $start = 0;
    my @items  = ();
    my $result;

    $self->player()->log("Fetching " . $objectid . "...");

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

    $self->player()->log(" .  Found " . scalar(@items) . " entries.");

    return @items unless $recurse;

    # recursively add sub-containers
    my @subitems = ();
    for (@items) {
        next unless $_->{"upnp:class"} =~ /container/;
        push @subitems, $self->fetchByObjectID($_->{id});
    }

    return @items, @subitems;
}

sub musicLibrary($self) {
    return $self->system()->musicLibrary();
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