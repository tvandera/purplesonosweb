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
    my @groups = values %{$self->{_zonegroups}};

    $self->log("Found " . scalar(@groups) . " zone groups at " . $self->lastUpdateReadable());
    for my $group (@groups) {
        $self->log("  $count: " . join(", ", map { $_->{ZoneName}  } @{$group}));
        $count++;
    }
}

sub UDN($self) {
    return $self->player()->UDN();
}

sub haveZoneInfo($self) {
    return defined $self->{_zonegroups};
}

# flattens values zonegroups
sub allZones($self) {
    my @allzones = map { @$_ } (values %{$self->{_zonegroups}});
    return { map { $_->{UUID} => $_ } @allzones };
}

sub coordinator($self) {
    return $self->zoneInfo($self->{_mycoordinator});
}

sub isCoordinator($self) {
    return $self->UDN() eq $self->{_mycoordinator};
}

sub numMembers($self) {
    return scalar @{$self->{_myzonemmembers}};
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

    my $info = $self->{_zonegroups}->{$coordinator};
    return scalar grep { $_->{UUID} eq $uuid } @$info;
}

# returns $coordinator and $groupinfo for ZoneGroup that
# contains player with $uuid
sub zoneGroupInfo($self, $uuid = undef) {
    return undef unless $self->haveZoneInfo();
    $uuid = $self->player()->UDN() unless defined $uuid;

    for my $coordinator (keys %{$self->{_zonegroups}}) {
        next unless $self->isInZoneGroup($coordinator, $uuid);
        return $coordinator, $self->{_zonegroups}->{$coordinator};
    }

    return undef, undef;
}

sub zoneInfo($self, $uuid = undef) {
    return undef unless $self->haveZoneInfo();
    $uuid = $self->player()->UDN() unless defined $uuid;
    return $self->allZones()->{$uuid};
}

sub processUpdate {
    my $self = shift;
    $self->processZoneGroupState(@_);
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
    for (@groups) {
        my $coordinator = $_->{Coordinator};
        my $members = $_->{ZoneGroupMember};
        $self->{_zonegroups}->{$coordinator} = $members;
        my ($myzoneinfo) = grep { $_->{UUID} eq $self->UDN() } @$members;
        next unless $myzoneinfo;

        # it's my zonegroup
        $self->{_myzoneinfo} = $myzoneinfo;
        $self->{_mycoordinator} = $coordinator;
        $self->{_myzonemmembers} = $members;
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
