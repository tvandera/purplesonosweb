package Plugins::WakeOnLan;

use Data::Dumper;
use strict;
use IO::Handle;
use Socket;


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
	# Remove colons
	$mac =~ tr/://d;
	# Magic packet is 6 bytes of FF followed by the MAC address 16 times
	my $magic = ("\xff" x 6) . (pack('H12', $mac) x 16);
	# Create socket
	socket(S, PF_INET, SOCK_DGRAM, getprotobyname('udp'))
		or die "socket: $!\n";
	# Enable broadcast
	setsockopt(S, SOL_SOCKET, SO_BROADCAST, 1)
		or die "setsockopt: $!\n";
	# Send the wakeup packet
	defined(send(S, $magic, 0, sockaddr_in(0x2fff, INADDR_BROADCAST)))
		or print "send: $!\n";
	close(S);
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
    return if ($main::ZONES{$zone}->{AV}->{TransportState} ne "PLAYING");

    main::Log (0, "Wakeup NAS");

    wakeup_nas();
}

1;
