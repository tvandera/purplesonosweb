
%Sonos::State::zones;
%Sonos::State::services;

sub addPlayer($properties)
{
    $udn = $properties[UUID];
    $zone = Sonos::State::Player->new($properties);
    $Sonos::State::zones[$udn] = $zone;
    return $zone;
}

sub findPlayer($key)
{
    our %zones;

    # find by uuid
    return $zones[$key] if defined $zones[$key];

    # find by location
    for my $zone (values %zones)
    {
        return $zone if $zone->location() == $key;
    }
}

package Sonos::Player;

sub new {
        my ($class, $properties) = @_;

        return bless {
                _properties  => $properties,
                _renderState => {},
                _avState => {},
        }, $class;
}

#  http://192.168.2.102:1400/xml/device_description.xml
sub location($self)
{
    return $self->_properties->{"LOCATION"};
}

sub updateRenderState($self, $renderstate)
{
    $self->_renderState = $renderstate;


    foreach my $key ("Volume", "Treble", "Bass", "Mute", "Loudness") {
        if ($tree->{InstanceID}->{$key}) {
            $main::ZONES{$zone}->{RENDER}->{$key} = $tree->{InstanceID}->{$key};
            $main::LASTUPDATE                 = $main::SONOS_UPDATENUM;
            $main::ZONES{$zone}->{RENDER}->{LASTUPDATE} = $main::SONOS_UPDATENUM++;
        }
    }
}

package Sonos::ZoneGroup;

1;
