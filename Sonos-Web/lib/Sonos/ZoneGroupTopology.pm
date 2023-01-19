package Sonos::Groups;

use v5.36;
use strict;
use warnings;

require UPnP::ControlPoint;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

use XML::Liberal;
use XML::LibXML::Simple qw(XMLin);
XML::Liberal->globally_override('LibXML');

use HTML::Entities;

use Data::Dumper;
use Carp;

package Sonos::GroupInfo;

sub new {
    my($self, $upnp, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _upnp => $upnp,
    }, $class;

    $self->setupServices();

    return $self;
}

sub DESTROY($self)
{
    $self{_subscription}->unsubscribe if defined $self->{_subscription};
}

sub info($self) {
    my $count = 0;
    for my $group (values %{$self->{_groups}}) {
        INFO "Group $count: " . join(", ", map { $_->{ZoneName} } @{$group});
        $count++;
    }
}

# called when zonegroups have changed
sub processUpdate ( $self, $service, %properties ) {
    my $tree = XMLin(
        decode_entities( $properties{"ZoneGroupState"} ),
        forcearray => [ "ZoneGroup", "ZoneGroupMember" ]
    );

    my @groups = @{ $tree->{ZoneGroups}->{ZoneGroup} };
    INFO "Found " . scalar(@groups) . " zone groups: ";
    $self->{_groups} = { map { $_->{Coordinator} => $_->{ZoneGroupMember} } @groups };

    $self->zoneGroupsInfo();
}

# not currently called, should be called from processZoneGroupTopology
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
