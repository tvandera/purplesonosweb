require Net::UPnP;

Net::UPnP::SetDebug(1);

use Net::UPnP::ControlPoint;

my $obj = Net::UPnP::ControlPoint->new();

while (1) {
    @dev_list = $obj->search(st =>'upnp:rootdevice', mx => 5);

    $devNum= 0;
    foreach $dev (@dev_list) {
        $device_type = $dev->getdevicetype();
        print "[$devNum] : " . $dev->getfriendlyname() . " (type: $device_type)\n";
        $devNum++;
    }

    sleep(2);
}