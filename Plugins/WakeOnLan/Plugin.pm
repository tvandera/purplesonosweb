package Plugins::WakeOnLan;

use Data::Dumper;
use strict;
use IO::Handle;
use Socket;
use Net::Wake;


###############################################################################
sub init {
    main::plugin_register("WakeOnLan", "Wake Up NASBUNTU when playing music");
    main::sonos_add_waiting("AV", "*", \&Plugins::WakeOnLan::av);
}

###############################################################################
sub quit {}

###############################################################################
sub wakeup_nas {
        my $mac = '00:17:a4:15:78:cf';
	my $ip = '192.168.2.255';
	Net::Wake::by_udp($ip, $mac);
}


###############################################################################
sub av {
    my ($what, $zone) = @_;

    main::sonos_add_waiting("AV", "*", \&Plugins::WakeOnLan::av);

    return if (!defined $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData});
    return if ($main::ZONES{$zone}->{AV}->{CurrentTrackMetaData} eq "");
    return if (!defined $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData}->{item});
    my $item = $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData}->{item};
    return if ($item->{"upnp:class"} ne "object.item.audioItem.musicTrack");
    return if ($main::ZONES{$zone}->{AV}->{TransportState} ne "TRANSITIONING");

    main::Log (0, "Wakeup NAS");

    wakeup_nas();
}

1;
