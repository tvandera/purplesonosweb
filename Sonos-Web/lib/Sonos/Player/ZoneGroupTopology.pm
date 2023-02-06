package Sonos::Player::ZoneGroupTopology;

use base 'Sonos::Player::Service';

use v5.36;
use strict;
use warnings;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

use HTML::Entities;

use Data::Dumper;
use Carp;

sub info($self) {
    my $count = 0;
    my @groups = values %{$self->{_groups}};

    $self->log("Found " . scalar(@groups) . " zone groups: ");
    for my $group (@groups) {
        $self->log("  $count: " . join(", ", map { $_->{ZoneName}  } @{$group}));
        $count++;
    }
}

sub UDN($self) {
    return $self->getPlayer()->UDN();
}

sub haveZoneInfo($self) {
    return defined $self->{_groups};
}

sub allZones($self) {
    my $allzones = [ map { @$_ } (values %{$self->{_groups}}) ];
    return $allzones;
}

sub isCoordinator($self) {
    my ($coordinator, $members) = $self->zoneGroupInfo();
    return $self->getUDN() eq $coordinator;
}

sub numMembers($self) {
    my ($coordinator, $members) = $self->zoneGroupInfo();
    return scalar @$members;
}

sub zoneName($self) {
    return undef unless $self->haveZoneInfo();
    return $self->zoneInfo()->{ZoneName};
}

sub icon($self) {
    return undef unless $self->haveZoneInfo();
    my $icon = $self->zoneInfo()->{Icon};
    $icon =~ s/^x-rincon-roomicon://;
    return $icon;
}

# check if $uuid is in ZoneGroup with Coordinator == $coordinator
sub isInZoneGroup($self, $coordinator, $uuid = undef) {
    return undef unless $self->haveZoneInfo();
    $uuid = $self->UDN() unless defined $uuid;

    my $info = $self->{_groups}->{$coordinator};
    return scalar grep { $_->{UUID} eq $uuid } @$info;
}

# returns $coordinator and $groupinfo for ZoneGroup that
# contains player with $uuid
sub zoneGroupInfo($self, $uuid = undef) {
    return undef unless $self->haveZoneInfo();
    $uuid = $self->getPlayer()->UDN() unless defined $uuid;

    for my $coordinator (keys %{$self->{_groups}}) {
        next unless $self->isInZoneGroup($coordinator, $uuid);
        return $coordinator, $self->{_groups}->{$coordinator};
    }

    return undef, undef;
}

sub zoneInfo($self, $uuid = undef) {
    return undef unless $self->haveZoneInfo();
    $uuid = $self->getPlayer()->UDN() unless defined $uuid;

    my @matchingzones = grep { $_->{UUID} eq $uuid } @{$self->allZones()};
    carp "No / More than one zone with uuid $uuid" unless scalar @matchingzones == 1;

    return $matchingzones[0];
}

# called when zonegroups have changed
sub processUpdate ( $self, $service, %properties ) {
    return unless $properties{"ZoneGroupState"};

    my $tree = XMLin(
        decode_entities( $properties{"ZoneGroupState"} ),
        forcearray => [ "ZoneGroup", "ZoneGroupMember" ]
    );

    my @groups = @{ $tree->{ZoneGroups}->{ZoneGroup} };
    $self->{_groups} = { map { $_->{Coordinator} => $_->{ZoneGroupMember} } @groups };

    $self->doCallBacks();

    $self->info();
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
