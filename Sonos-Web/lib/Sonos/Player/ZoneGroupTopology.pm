package Sonos::Player::ZoneGroupTopology;

use base 'Sonos::Player::Service';

use v5.36;
use strict;
use warnings;

sub processUpdate {
    my $self = shift;
    $self->system()->processZoneGroupState(@_);
    $self->SUPER::processUpdate(@_)
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
        my $members = $_->{ZoneGroupMember};
        $self->{_zonegroups}->{$coordinator} = $members;
        my ($myzoneinfo) = grep { $_->{UUID} eq $self->UDN() } @$members;
        next unless $myzoneinfo;

        # it's my zonegroup
        $self->{_myzoneinfo} = $myzoneinfo;
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
sub linkZone($self, $zone) {
    my $player = $self->player();

    # No need to do anything
    return 0 if ($player->zoneGroupTopology()->coordinator() eq $zone);

    $player->avTransport()->setURI("x-rincon:" . $zone);
    return 1;
}

# puts $self and $zone in the same ZoneGroup
# $zone will be coordinator
sub linkToZone($self, $zone) {
    my $player = $self->player();
    my $coordinator = $self->player($zone);

    # No need to do anything
    return 0 if ($self->coordinator() eq $zone);

    $player->avTransport()->setURI("x-rincon:" . $coordinator->UDN());
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