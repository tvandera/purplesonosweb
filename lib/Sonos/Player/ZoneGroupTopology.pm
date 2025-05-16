package Sonos::Player::ZoneGroupTopology;

use base 'Sonos::Player::Service';

use v5.36;
use strict;
use warnings;

use XML::Liberal        ();
use XML::LibXML::Simple qw( XMLin );
XML::Liberal->globally_override('LibXML');

use HTML::Entities qw( decode_entities );

use Types::Serialiser ();

sub info($self) {
    my $count  = 0;
    my @groups = keys %{ $self->{_zonegroups} };

    $self->log( "Found "
          . scalar(@groups)
          . " zone groups at "
          . $self->lastUpdateReadable() );
    for my $coordinator (@groups) {
        my @members = $self->members($coordinator);
        $self->log(
            "  $count: " . join(
                ", ",
                map {
                    my $uuid          = $_->{UUID};
                    my $name          = $_->{ZoneName};
                    my $isCoordinator = $coordinator eq $uuid;
                    $name . ( $isCoordinator ? " [C]" : "" )
                } @members
            )
        );
        $count++;
    }
}

sub TO_JSON( $self, $recurse = 1 ) {
    return {
        "last_update" => $self->lastUpdate(),
        "icon"        => $self->icon(),
        "img"         => "icons/zone/" . $self->icon(),
        "name"        => $self->friendlyName(),
        "coordinator" => $self->coordinator()->zoneName(),
        "is_coord"    => Types::Serialiser::as_bool( $self->isCoordinator() ),
        "members"     => [ $self->memberInfo() ],
    };
}

sub friendlyName($self) {
    my $groupname  = $self->coordinator()->friendlyName();
    my $num_linked = $self->numMembers() - 1;
    $groupname .= " + " . $num_linked if $num_linked;
    return $groupname;
}

sub UDN($self) {
    return $self->player()->UDN();
}

sub player( $self, $uuid = undef ) {
    return $self->SUPER::player() unless $uuid;
    return $self->system()->player($uuid);
}

sub haveZoneInfo($self) {
    return defined $self->{_zonegroups};
}

# flattens values zonegroups
# returns a map UDN => ZoneGroup
sub allZones($self) {
    my @allzones = map { @$_ } ( values %{ $self->{_zonegroups} } );
    return { map { $_->{UUID} => $_ } @allzones };
}

sub coordinator($self) {
    return $self->player( $self->{_mycoordinator} );
}

sub isCoordinator( $self, $uuid = undef ) {
    return               unless $self->haveZoneInfo();
    $uuid = $self->UDN() unless defined $uuid;

    return $uuid eq $self->{_mycoordinator};
}

sub members( $self, $uuid = undef ) {
    return               unless $self->haveZoneInfo();
    $uuid = $self->UDN() unless defined $uuid;

    my ( $coordinator, $members ) = $self->zoneGroupInfo($uuid);
    return @$members;
}

sub memberNames( $self, $uuid = undef ) {
    return map { $_->{ZoneName} } $self->members($uuid);
}

sub memberInfo( $self, $uuid = undef ) {
    return map {
        my $icon = $self->icon( $_->{UUID} );
        {
            "name" => $_->{ZoneName},
            "icon" => $icon,
            "img"  => "icons/zone/" . $icon,
        }
    } $self->members($uuid);
}

sub numMembers( $self, $uuid = undef ) {
    return scalar $self->members($uuid);
}

sub zoneName( $self, $uuid = undef ) {
    return               unless $self->haveZoneInfo();
    $uuid = $self->UDN() unless defined $uuid;

    return $self->zoneInfo($uuid)->{ZoneName};
}

sub icon( $self, $uuid = undef ) {
    return               unless $self->haveZoneInfo();
    $uuid = $self->UDN() unless defined $uuid;

    my $icon = $self->zoneInfo($uuid)->{Icon};
    $icon =~ s/^x-rincon-roomicon://;
    return $icon;
}

# check if $uuid is in ZoneGroup with Coordinator == $coordinator
sub isInZoneGroup( $self, $coordinator, $uuid = undef ) {
    return               unless $self->haveZoneInfo();
    $uuid = $self->UDN() unless defined $uuid;

    my $info = $self->{_zonegroups}->{$coordinator};
    return scalar grep { $_->{UUID} eq $uuid } @$info;
}

# returns $coordinator and $groupinfo for ZoneGroup that
# contains player with $uuid
sub zoneGroupInfo( $self, $uuid = undef ) {
    return                         unless $self->haveZoneInfo();
    $uuid = $self->player()->UDN() unless defined $uuid;

    for my $coordinator ( keys %{ $self->{_zonegroups} } ) {
        next unless $self->isInZoneGroup( $coordinator, $uuid );
        return $coordinator, $self->{_zonegroups}->{$coordinator};
    }

    return, undef;
}

sub zoneInfo( $self, $uuid = undef ) {
    return                         unless $self->haveZoneInfo();
    $uuid = $self->player()->UDN() unless defined $uuid;
    return $self->allZones()->{$uuid};
}

sub numZoneGroups($self) {
    return scalar keys %{ $self->{_zonegroups} };
}

sub processUpdate {
    my $self = shift;
    $self->processZoneGroupState(@_);
    $self->SUPER::processUpdate(@_);
}

# called when zonegroups have changed
sub processZoneGroupState ( $self, $service, %properties ) {
    return unless $properties{"ZoneGroupState"};

    my $tree = XMLin(
        decode_entities( $properties{"ZoneGroupState"} ),
        forcearray => [ "ZoneGroup", "ZoneGroupMember" ]
    );

    my @groups = @{ $tree->{ZoneGroups}->{ZoneGroup} };

    delete $self->{_zonegroups};
    delete $self->{_myzoneinfo};
    delete $self->{_mycoordinator};

    for (@groups) {
        my $coordinator = $_->{Coordinator};
        my $members     = $_->{ZoneGroupMember};
        $self->{_zonegroups}->{$coordinator} = $members;
        my ($myzoneinfo) = grep { $_->{UUID} eq $self->UDN() } @$members;
        next unless $myzoneinfo;

        # it's my zonegroup
        $self->{_myzoneinfo}    = $myzoneinfo;
        $self->{_mycoordinator} = $coordinator;
    }
}

# not currently called, should be called from processUpdate
sub processThirdPartyMediaServers ( $self, $properties ) {
    my %mapping = (
        "SA_RINCON1_" => "Rhapsody",
        "SA_RINCON4_" => "Pandora",
        "SA_RINCON6_" => "Sirius"
    );

    my $tree =
      XMLin( decode_entities( $properties->{"ThirdPartyMediaServers"} ),
        forcearray => ["Service"] );
    for my $item ( @{ $tree->{Service} } ) {
        while ( my ( $rincon, $service ) = each(%mapping) ) {
            Sonos::State::addService( $service, $item )
              if ( $item->{UDN} =~ $rincon );
        }
    }
}

# all zones in the same ZoneGroup
# $self will be coordinator
sub linkAllZones($self) {
    my $ret = 0;
    $ret ||= $self->linkZone($_) for $self->allZones();
    return $ret;
}

# puts $self and $zone in the same ZoneGroup
# $self will be coordinator
sub linkZone( $self, $zone ) {
    my $player = $self->player();

    # No need to do anything
    return 0 if ( $player->zoneGroupTopology()->coordinator() eq $zone );

    $player->avTransport()->setURI( "x-rincon:" . $zone );
    return 1;
}

# puts $self and $zone in the same ZoneGroup
# $zone will be coordinator
sub linkToZone( $self, $zone ) {
    my $player      = $self->player();
    my $coordinator = $self->player($zone);

    # No need to do anything
    return 0 if ( $self->coordinator() eq $zone );

    $player->avTransport()->setURI( "x-rincon:" . $coordinator->UDN() );
    return 1;
}

# removes $self from any ZoneGroup
sub unlink($self) {
    return 0 if $self->numMembers() == 1;

    my $av = $self->player()->avTransport();
    $av->standaloneCoordinator();
    $av->setQueue();
    return 1;
}

1;
