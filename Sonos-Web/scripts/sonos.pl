#!/usr/bin/env perl

use feature 'unicode_strings';

use strict;
use warnings;

use UPnP::ControlPoint;
use Socket;
use IO::Select;
use IO::Handle;
use Data::Dumper;
use HTML::Parser;
use HTML::Entities;
use URI::Escape;

use XML::Liberal;
use XML::LibXML::Simple   qw(XMLin);
XML::Liberal->globally_override('LibXML');

use HTTP::Daemon;
use HTML::Template;
use HTML::Template::Compiled;
use LWP::MediaTypes qw(add_type);
use POSIX qw(strftime);
use Encode qw(encode decode);
use IO::Compress::Gzip qw(gzip);
use LWP::UserAgent;
use SOAP::Lite maptype => {};
use MIME::Base64;
use Carp qw(cluck);
use JSON;
use Digest::SHA qw(sha256_hex);
use File::Slurp;
use Time::HiRes qw(  gettimeofday );
use Image::Magick;
use File::Slurp;

$main::VERSION        = "0.72";


$| = 1;

foreach my $arg (@ARGV) {
    $main::MAX_LOG_LEVEL = 4 if ($arg eq "-debug");
    $main::MAX_LOG_LEVEL = 1 if ($arg eq "-alert");
    doconfig() if ($arg eq "-config");
}

if ($main::MUSICDIR ne "") {
    $main::MUSICDIR = "$main::MUSICDIR/SonosWeb";
    if (! -d $main::MUSICDIR) {
        mkdir ($main::MUSICDIR);
        die "Couldn't create directory '$main::MUSICDIR'" if (! -d $main::MUSICDIR);
    }
}

$SIG{INT} = "main::quit";
$SIG{PIPE} = sub {};
$SIG{CHLD} = \&main::sigchld;

$Data::Dumper::Indent  = 1;
@main::TIMERS          = ();
$main::SONOS_UPDATENUM = time();
%main::PREFS           = ();
%main::CHLD            = ();
$main::ZONESUPDATE     = 0;

@main::profiles = ();

sub sonos_profile_print {
    print "Profiling info:\n";
    my $prev = 0;
    foreach (@main::profiles) {
        printf "%d;%f\n", $_->{line}, $_->{time} - $prev;
        $prev = $_->{time};
    }
}

sub sonos_profile {
    my ($line) = @_;
    push @main::profiles, { "time" => scalar gettimeofday, "line" => $line };
}

sub enc {
    my $ent = shift;
    $ent = "" if ref $ent;
    $ent = encode_entities($ent);
    return $ent;
}


###############################################################################
use POSIX ":sys_wait_h";
sub sigchld {
    my $child;
    while (($child = waitpid(-1,WNOHANG)) > 0) {
        delete $main::CHLD{$child};
    }
    $SIG{CHLD} = \&main::sigchld;
}

###############################################################################
sub quit {
    plugin_quit();
    http_quit();
    sonos_quit();
    # sonos_profile_print();
    Log (0, "Shutting Down");
    exit 0;
}

###############################################################################
# main
sub main {
    Log (0, "Starting v$main::VERSION at http://localhost:$main::HTTP_PORT\n");

    add_type("text/css" => qw(css));
    $main::useragent = LWP::UserAgent->new(env_proxy  => 1, keep_alive => 2, parse_head => 0);
    $main::daemon = HTTP::Daemon->new(LocalPort => $main::HTTP_PORT, ReuseAddr => 1, ReusePort => 1) || die;

    if ($main::SEARCHADDR) {
        $main::cp = UPnP::ControlPoint->new (SearchAddr => $main::SEARCHADDR);
    } else {
        $main::cp = UPnP::ControlPoint->new ();
    }

    my $search = $main::cp->searchByType("urn:schemas-upnp-org:device:ZonePlayer:1", \&main::upnp_search_cb);

    my @selsockets = $main::cp->sockets();
    @selsockets = (@selsockets, $main::daemon);
    $main::select = IO::Select->new(@selsockets);

    http_register_handler("/getaa", \&http_albumart_request);
    http_register_handler("/getAA", \&http_albumart_request);

    add_macro("Play", "/simple/control.html?zone=%zone%&action=Play");
    add_macro("Pause", "/simple/control.html?zone=%zone%&action=Pause");
    add_macro("Next", "/simple/control.html?zone=%zone%&action=Next");
    add_macro("Previous", "/simple/control.html?zone=%zone%&action=Previous");

    sonos_containers_init();
    sonos_prefsdb_load();
    sonos_renew_subscriptions();
    plugin_load();

    # MAIN LOOP
    while (1) {

        # Check the callbacks we have waiting
        my $timeout = 5;
        my $now = time;
        while ($#main::TIMERS >= 0) {
            if ($main::TIMERS[0][0] <= $now) {
                my($time, $callback, @args) = @{shift @main::TIMERS};
                &$callback(@args);
            } else {
                $timeout = $main::TIMERS[0][0] - $now;
                last;
            }
        }

        # Find if any sockets are ready for reading
        my @sockets = $main::select->can_read($timeout);

        # Call the handlers for the sockets
        for my $sock (@sockets) {
            if ($sock == $main::daemon) {
                my $c = $main::daemon->accept;
                my $r = $c->get_request;
                http_handle_request($c, $r);
            } elsif (defined $main::SOCKETCB{$sock}) {
                &{$main::SOCKETCB{$sock}}();
            } else {
                $main::cp->handleOnce($sock);
            }
        }
    }
}



###############################################################################
# SONOS
###############################################################################
%main::UPDATEID = (
    ShareIndexInProgress => 0,
    ShareIndexInProgress2 => 0,
    ShareListUpdateID => "",
    MasterRadioUpdateID => "",
    SavedQueuesUpdateID => ""
);

###############################################################################
sub sonos_quit {
    foreach my $sub (keys %main::SUBSCRIPTIONS) {
        Log (2, "Unsubscribe $sub");
        $main::SUBSCRIPTIONS{$sub}->unsubscribe;
    }
}
###############################################################################

# tell sonos to update its music database
sub sonos_reindex {
    if ($main::UPDATEID{ShareIndexInProgress} || $main::UPDATEID{ShareIndexInProgress2}) {
        Log (2, "Alreadying reindexing");
        return;
    }
    upnp_content_dir_refresh_share_index();
}

###############################################################################
sub sonos_location_to_id {
    # location is smtg like: http://192.168.2.102:1400/xml/device_description.xml
    my ($location) = @_;

    foreach my $zone (keys %main::ZONES) {
        return $zone if ($main::ZONES{$zone}->{Location} eq $location);
    }
    return undef;
}


###############################################################################
sub sonos_music_isfav {
    my ($mpath) = @_;
    return $mpath =~ /^FV:/;
}

###############################################################################
sub sonos_music_realclass {
    my ($entry) = @_;
    my $class = $entry->{"upnp:class"};

    return $class if (!$entry->{'r:resMD'});
    my $meta = XMLin($entry->{'r:resMD'});
    return $class if (!$meta->{item}->{"upnp:class"});
    return $meta->{item}->{"upnp:class"};
}

###############################################################################
sub sonos_music_class {
    # Given a music_path, looks up an returns the class
    my ($mpath) = @_;

    my $entry = sonos_music_entry($mpath);
    return undef if (!defined $entry);
    return $entry->{"upnp:class"};
}
###############################################################################
sub sonos_music_entry {
    # Given a music_path, returns info on this music entry
    my ($mpath) = @_;
    my $type = substr ($mpath, 0, index($mpath, ':'));

    if (exists $main::ITEMS{$mpath}) {
    } elsif (defined $main::HOOK{"ITEM_$type"}) {
        sonos_process_hook("ITEM_$type", $mpath);
    } else {
        my ($zone) = split(",", $main::UPDATEID{ShareListUpdateID});
        my $entry =  upnp_content_dir_browse($zone, $mpath, "BrowseMetadata");
        $main::ITEMS{$mpath} = $entry->[0] if (defined $entry->[0]);
    }

    return $main::ITEMS{$mpath};
}
###############################################################################
sub sonos_music_albumart {
    my ($entry) = @_;
    my $art = $entry->{"upnp:albumArtURI"};
    return $art if $art;

    my $parent = $entry->{parentID};
    $art = sonos_music_albumart(sonos_music_entry($parent)) if $parent;
    $entry->{"upnp:albumArtURI"} = $art;

    return $art
}
###############################################################################
sub sonos_is_radio {
    my ($mpath) = @_;

    my $entry = sonos_music_entry($mpath);
    return undef if (!defined $entry);
    my $uri = $entry->{res}->{content};
    return ($uri =~ m/^x-sonosapi-stream:/) ||
           ($uri =~ m/^x-sonosapi-radio:/) ||
           ($uri =~ m/^x-sonosapi-pndrradio:/);
}


###############################################################################
sub sonos_avtransport_set_radio {
    my ($zone, $mpath) = @_;

    my @parts = split("/", $mpath);

    my $entry = sonos_music_entry($mpath);

# So, I'm very lazy :-)
    my $urimetadata = '&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;' . $entry->{id} . '&quot; parentID=&quot;' . $entry->{parentID} . '&quot; restricted=&quot;true&quot;&gt;&lt;dc:title&gt;'. $entry->{"dc:title"} .  '&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;&lt;desc id=&quot;cdudn&quot; nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;RINCON_AssociatedZPUDN&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;';


    upnp_avtransport_set_uri($zone, $entry->{res}->{content}, decode_entities($urimetadata));
    upnp_avtransport_play($zone);

    return;
}
###############################################################################
sub sonos_avtransport_set_queue {
    my ($zone) = @_;

    upnp_avtransport_set_uri($zone, "x-rincon-queue:" . $zone . "#0", "");

    return;
}
###############################################################################
sub sonos_avtransport_set_linein {
    my ($zone, $mpath) = @_;

    my @parts = split("/", $mpath);

    my $entry = sonos_music_entry($mpath);

# So, I'm very lazy :-)
    my $urimetadata = '&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;AI:0&quot; parentID=&quot;AI:&quot; restricted=&quot;true&quot;&gt;&lt;dc:title&gt;' . $parts[2] .'&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem&lt;/upnp:class&gt;&lt;desc id=&quot;cdudn&quot; nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;'. $entry->{zone} . '&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;';

    upnp_avtransport_set_uri($zone, $entry->{res}->{content}, decode_entities($urimetadata));

    return;
}
###############################################################################
sub sonos_avtransport_add {
    my ($zone, $mpath, $queueSlot) = @_;

    my $entry = sonos_music_entry($mpath);
    Log(3, "before mpath = $mpath entry = " . Dumper($entry));

    if ($entry->{"upnp:class"} eq "object.item.audioItem.audioBroadcast") {
        return
    }

    my $type = substr ($mpath, 0, index($mpath, ':'));
    my $metadata = "";
    if (defined $main::HOOK{"META_$type"}) {
        $metadata = sonos_process_hook("META_$type", $mpath, $entry);
    }
    upnp_avtransport_add_uri($zone, $entry->{res}->{content}, $metadata, $queueSlot);

    return;
}

###############################################################################
sub sonos_add_waiting {
    my $what = shift @_;
    my $zone = shift @_;
    my $cb   = shift @_;

    push @{$main::WAITING{$what}{$zone}}, [$cb, @_];
}
###############################################################################
sub sonos_process_waiting {
    my ($what, $zone) = @_;

    sonos_process_waiting_internal ($what, $zone, $what, $zone) if (defined $zone);
    sonos_process_waiting_internal ($what, "*", $what, $zone);
    sonos_process_waiting_internal ("*", $zone, $what, $zone) if (defined $zone);
    sonos_process_waiting_internal ("*", "*", $what, $zone);
}

###############################################################################
sub sonos_process_waiting_internal {
    my ($mwhat, $mzone, $what, $zone) = @_;

    return if (!defined $main::WAITING{$mwhat}{$mzone});
    my @waiting = @{$main::WAITING{$mwhat}{$mzone}};
    @{$main::WAITING{$mwhat}{$mzone}} = ();

    while ($#waiting >= 0) {
        my($callback, @args) = @{shift @waiting};
        &$callback($what, $zone, @args);
    }
}


###############################################################################
sub sonos_link_all_zones {
    my ($masterzone) = @_;

    foreach my $linkedzone (keys %main::ZONES) {
        next if ($linkedzone eq $masterzone);
        sonos_link_zone($masterzone, $linkedzone);
    }

}
###############################################################################
sub sonos_link_zone {
    my ($masterzone, $linkedzone) = @_;

    # No need to do anything
    return if ($main::ZONES{$linkedzone}->{Coordinator} eq $masterzone);

    my $result = upnp_avtransport_set_uri($linkedzone, "x-rincon:" . $masterzone, "");
    if ($result->isSuccessful) {
        $main::ZONES{$linkedzone}->{Coordinator} = $masterzone ;
        push @{$main::ZONES{$masterzone}->{Members}}, $linkedzone ;
    }
    return $result;
}

###############################################################################
sub sonos_unlink_zone {
    my ($linkedzone) = @_;

    # First if this is a coordinator for any zones, make a new coordinator
    my $newcoord;
    foreach my $zone (keys %main::ZONES) {
        next if ($zone eq $linkedzone);
        if ($linkedzone eq $main::ZONES{$zone}->{Coordinator}) {
            if ($newcoord) {
                sonos_link_zone($newcoord, $zone);
            } else {
                upnp_avtransport_standalone_coordinator($zone);
                upnp_avtransport_set_uri($zone, "x-rincon-queue:" . $zone . "#0", "");
                $main::ZONES{$zone}->{Coordinator} = $zone;
                $main::ZONES{$zone}->{Members} = [ $zone ];
                $main::ZONES{$linkedzone}->{Members} = [ $linkedzone ];
                $newcoord = $zone
            }
        }
    }

    # No need to do anything else
    return if ($main::ZONES{$linkedzone}->{Coordinator} eq $linkedzone);

    upnp_avtransport_standalone_coordinator($linkedzone);
    my $result = upnp_avtransport_set_uri($linkedzone, "x-rincon-queue:" . $linkedzone . "#0", "");

    # Perform the unlink locally also
    $main::ZONES{$linkedzone}->{Coordinator} = $linkedzone if ($result->isSuccessful);

    return $result;
}

###############################################################################
sub sonos_add_radio {
    my ($name, $station) = @_;
    Log(3, "Adding radio name:$name, station:$station");

    $station = substr($station, 5) if (substr($station, 0, 5) eq "http:");
    $name = enc($name);

    my $item = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" ' .
               'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" ' .
               'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">' .
               '<item id="" restricted="false"><dc:title>' .
               $name . '</dc:title><res>x-rincon-mp3radio:' .
               $station .  '</res></item></DIDL-Lite>';

    my ($zone) = split(",", $main::UPDATEID{MasterRadioUpdateID});
    return upnp_content_dir_create_object($zone, "R:0/0", $item);
}


###############################################################################
# UTILS
###############################################################################
###############################################################################
# Add a new command to the list of commands a user can select
sub add_macro {
    my ($friendly, $url) = @_;

    $main::Macros{$friendly} = $url;
}
###############################################################################
# Delete a macro from the list of macros a user can select
sub del_macro {
    my ($friendly) = @_;

    delete $main::Macros{$friendly};
}
###############################################################################
sub process_macro_url {
my ($url, $zone, $artist, $album, $song) = @_;

    if (substr($url, 0, 4) ne "http") {
        $url = main::http_base_url() . $url;
    }
    $url =~ s/%zone%/$zone/g;
    $url =~ s/%artist%/$artist/g;
    $url =~ s/%album%/$album/g;
    $url =~ s/%song%/$song/g;

    my $curtrack = $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData};
    if ($curtrack) {
        $url =~ s/%curartist%/$curtrack->{item}->{"dc:creator"}/g;
        $url =~ s/%curalbum%/$curtrack->{item}->{"upnp:album"}/g;
        $url =~ s/%cursong%/$curtrack->{item}->{"dc:title"}/g;
    }

    return $url;
}
##############################################################################_#
#Copied from XML::XQL
sub trim
{
    $_[0] =~ s/^\s+//;
    $_[0] =~ s/\s+$//;
    $_[0];
}

###############################################################################
main();
