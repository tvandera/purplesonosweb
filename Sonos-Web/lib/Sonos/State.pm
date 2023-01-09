package Sonos::State;

%Sonos::State::zones;
%Sonos::State::services;

sub addZone($properties)
{
    $udn = $properties[UUID];
    $zone = $Sonos::State::Zone->new($properties);
    $Sonos::State::zones[$udn] = $zone;
    return $zone;
}

package Sonos::State::Zone;

sub new {
        my ($class, $properties) = @_;

        return bless {
                _properties  => $properties,
                _renderState => {},
                _avState => {},
        }, $class;
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
