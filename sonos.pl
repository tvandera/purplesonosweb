#!/usr/bin/perl

use lib "./UPnP/lib";
use lib ".";
use UPnP::ControlPoint;
use Socket;
use IO::Select;
use IO::Handle;
use Data::Dumper;
use HTML::Parser;
use HTML::Entities;
use URI::Escape;
use XML::Simple;
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
use strict;
use Carp qw(cluck);
use JSON;
use Digest::SHA qw(sha256_hex);
use File::Slurp;
use Time::HiRes qw(  gettimeofday );


$main::VERSION        = "0.72";

###############################################################################
# Default config if config.pl doesn't exist
$main::MAX_LOG_LEVEL  = 0;    # Lower, the less output
$main::HTTP_PORT      = 8001; # Port our fake http server listens on
$main::MAX_SEARCH     = 500;  # Default max search results to return
$main::RENEW_SUB_TIME = 1800; # How often do we do a UPnP renew in seconds
$main::DEFAULT        = "index.html";
$main::AACACHE        = 3600; # How long do we tell browser to cache album art in secs
$main::MUSICDIR       = "";   # Local directory that sonos indexs that we can create music files in
$main::PASSWORD       = "";   # Password for basic auth
$main::IGNOREIPS      = "";   # Ignore this ip
$main::AACACHEDIR     = "aa_cache";

do "./config.pl" if (-f "./config.pl");
foreach my $ip (split (",", $main::IGNOREIPS)) {
    $UPnP::ControlPoint::IGNOREIP{$ip} = 1;
}

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

if ($main::AACACHEDIR ne "") {
    if (! -d $main::AACACHEDIR) {
        mkdir ($main::AACACHEDIR);
        die "Couldn't create directory '$main::AACACHEDIR'" if (! -d $main::AACACHEDIR);
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
    return encode_entities($ent);
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
sub doconfig {
    print  "Configure the defaults for sonos.pl by creating a config.pl file.\n";
    print  "Press return or enter key to keep current values.\n";
    print  "Remove the config.pl to reset to the system defaults.\n";
    print  "\n";
    print  "Port to listen on [$main::HTTP_PORT]: ";
    my $port = int(<STDIN>);
    $port = $main::HTTP_PORT if ($port == 0);
    $port = 8001 if ($port > 0xffff || $port <= 0);

    print  "Max log level 0=crit 4=debug [$main::MAX_LOG_LEVEL]: ";
    my $loglevel = int(<STDIN>);
    $loglevel = $main::MAX_LOG_LEVEL if ($loglevel == 0);
    $loglevel = 1 if ($loglevel < 0 || $loglevel > 4);

    print  "Max search results [$main::MAX_SEARCH]: ";
    my $maxsearch = int(<STDIN>);
    $maxsearch = $main::MAX_SEARCH if ($maxsearch == 0);
    $maxsearch = 500 if ($maxsearch < 0);

    print  "Default web page, must exist in html directory [$main::DEFAULT]: ";
    my $defaultweb = <STDIN>;
    $defaultweb =~ s/[\r\n]//m;
    if ($defaultweb eq " ") {
        $defaultweb = "";
    } elsif ($defaultweb eq "") {
        $defaultweb = $main::DEFAULT;
    }
    die "The file html/$defaultweb was not found\n" if ($defaultweb ne "" && ! -f "html/$defaultweb");

    print  "\n";
    print  "Location on local disk that Sonos indexes, a subdirectory SonosWeb will be created.\n";
    print  "Use forward slashes only (ex c:/Music), enter single space to clear [$main::MUSICDIR]: ";
    my $musicdir = <STDIN>;
    $musicdir =~ s/[\r\n]//m;
    if ($musicdir eq " ") {
        $musicdir = "";
    } elsif ($musicdir eq "") {
        $musicdir = "$main::MUSICDIR";
    }
    die "$musicdir is not a directory\n" if ($musicdir ne "" &&  ! -d $musicdir);

    print  "\n";
    print  "Password for access to web site. (Notice, this isn't secure at all.)\n";
    print  "Enter single space to clear [$main::PASSWORD]: ";
    my $password = <STDIN>;
    $password =~ s/[\r\n]//m;
    if ($password eq " ") {
        $password = "";
    } elsif ($password eq "") {
        $password = "$main::PASSWORD";
    }

    print  "\n";
    print  "Ignore traffic from these comma seperated ips\n";
    print  "Enter single space to clear [$main::IGNOREIPS]: ";
    my $ignoreips = <STDIN>;
    $ignoreips =~ s/[\r\n]//m;
    if ($ignoreips eq " ") {
        $ignoreips = "";
    } elsif ($ignoreips eq "") {
        $ignoreips = "$main::IGNOREIPS";
    }

    open (CONFIG, ">./config.pl");
    print CONFIG "# This file uses perl syntax\n";
    print CONFIG "\$main::HTTP_PORT = $port;\n";
    print CONFIG "\$main::MAX_LOG_LEVEL = $loglevel;\n";
    print CONFIG "\$main::MAX_SEARCH = $maxsearch;\n";
    print CONFIG "\$main::DEFAULT = \"$defaultweb\";\n";
    print CONFIG "\$main::MUSICDIR =\"$musicdir\";\n";
    print CONFIG "\$main::PASSWORD =\"$password\";\n";
    print CONFIG "\$main::IGNOREIPS =\"$ignoreips\";\n";
    close CONFIG;
    print  "\nPlease restart sonos.pl now\n";

    exit 0;
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
    Log (0, "Starting up version $main::VERSION!\n" .
    "If the application doesn't seem to work:\n" . 
    "  * you may need to disable your firewall or allow the application\n" .
    "  * make sure the computer is on the same network as Sonos boxes\n" .
    "  * make sure the Sonos Controller software isn't running on the same computer\n" .
    "\n" . 
    "Now, point your browser to http://localhost:$main::HTTP_PORT and leave this running\n");

    add_type("text/css" => qw(css));
    $main::useragent = LWP::UserAgent->new(env_proxy  => 1, keep_alive => 2, parse_head => 0);
    $main::daemon = HTTP::Daemon->new(LocalPort => $main::HTTP_PORT, Reuse => 1) || die;
    $main::cp = UPnP::ControlPoint->new ();
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
    sonos_musicdb_load();
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
# PLUGINS
###############################################################################

###############################################################################
sub plugin_load {
    Log(1, "Loading Plugins");

    eval "us" . "e lib '.'"; # Defeat pp stripping
    opendir(DIR, "Plugins") || return;

    for my $plugin (readdir(DIR)) {
        if ($plugin =~ /(.+)\.pm$/) {
            $main::PLUGINS{$plugin} = () if (!$main::PLUGINS{$plugin});
            $main::PLUGINS{$plugin}->{require} = "Plugins::" . $1;

        } elsif (-d "Plugins/$plugin" && -e "Plugins/$plugin/Plugin.pm") {
            $main::PLUGINS{$plugin} = () if (!$main::PLUGINS{$plugin});
            $main::PLUGINS{$plugin}->{require} = "Plugins::" . $plugin . "::Plugin";
            if ( -d "Plugins/$plugin/html") {
                $main::PLUGINS{$plugin}->{html} = "Plugins/$plugin/html/";
            }

        }
    }
    closedir(DIR);

    # First load the plugins
    foreach my $plugin (keys %main::PLUGINS) {
	eval "require ". $main::PLUGINS{$plugin}->{require};
	if ($@) {
            Log(0, "Did not load $plugin: " . $@);
            delete $main::PLUGINS{$plugin};
            next;
        }
    }

    # Now init the plugins.  We do in two steps so plugin inits can talk to other plugins
    foreach my $plugin (keys %main::PLUGINS) {
        eval "Plugins::${plugin}::init();";
	if ($@) {
            Log(0, "Did not init $plugin: " . $@);
            delete $main::PLUGINS{$plugin};
            next;
        }
    }
}

###############################################################################
sub plugin_register {
    my ($plugin, $name, $link, $tmplhook) = @_;

    $main::PLUGINS{$plugin}->{name} = $name;
    $main::PLUGINS{$plugin}->{link} = $link;
    $main::PLUGINS{$plugin}->{tmplhook} = $tmplhook;
}

###############################################################################
sub plugin_quit {
    foreach my $plugin (keys %main::PLUGINS) {
        eval "Plugins::${plugin}::quit();";
	if ($@) {
            Log(0, "Can not quit $plugin: " . $@);
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
sub sonos_reindex {
    if ($main::UPDATEID{ShareIndexInProgress} || $main::UPDATEID{ShareIndexInProgress2}) {
        Log (2, "Alreadying reindexing");
        return;
    }
    upnp_content_dir_refresh_share_index();
}

###############################################################################
sub sonos_fetch_music {
    $main::UPDATEID{ShareIndexInProgress2} = 1;

    my ($zone) = split(",", $main::UPDATEID{ShareListUpdateID});
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");

    if (! defined $contentDir) {
        if ($zone eq "") {
            Log(0, "Main zone not found yet, will retry.  Windows XP *WILL* require rerunning SonosWeb after selecting 'Unblock' in the Windows Security Alert.");
        } else {
            Log(1, "$zone not available, will retry");
        }
        add_timeout (time()+5, \&sonos_fetch_music);
        return
    }

    undef %main::REINDEX_DATA;

    Log (1, "Fetching Music DB");
    $main::REINDEX{start} = 0;
    sonos_fetch_music_callback();
}

###############################################################################
sub sonos_fetch_music_callback {
    # We only do 200 at a time otherwise we lock out everything else

    my ($zone) = split(",", $main::UPDATEID{ShareListUpdateID});
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    my $contentDirProxy = $contentDir->controlProxy; 
    my $result = $contentDirProxy->Browse("A:TRACKS", 'BrowseDirectChildren', 
                                          'dc:title,res,dc:creator,upnp:artist,upnp:album', 
                                          $main::REINDEX{start}, 200, "");

    if (!$result->isSuccessful) {
        Log (2, "Failed to fetch all tracks: " . Dumper($result));
        Log (3, "Proxy is: " . Dumper($main::REINDEX{contentDirProxy}));
        $main::UPDATEID{ShareIndexInProgress2} = 0;
        $main::MUSICUPDATE = $main::SONOS_UPDATENUM++;
        sonos_containers_del("A:");
        sonos_process_waiting("MUSIC");
        return;
    }

    $main::REINDEX{start} += $result->getValue("NumberReturned");
    Log (2, "DB: $main::REINDEX{start} of " . $result->getValue("TotalMatches"));

    my $results = $result->getValue("Result");
    my $tree = XMLin($results, forcearray => ["item"]);

    foreach my $objectid (keys %{$tree->{item}}) {
        my $entry = $tree->{item}{$objectid};
        my $artist = $entry->{"dc:creator"};
        my $album = $entry->{"upnp:album"};
        my $title = $entry->{"dc:title"};
        $artist = "" if (! $entry->{"dc:creator"});
        $album  = "" if (! $entry->{"upnp:album"});

#Only copy the stuff we want
        $main::REINDEX_DATA{$artist}{$album}{$title} = $objectid
    }

    if ($main::REINDEX{start} >= $result->getValue("TotalMatches")) {
        %main::MUSIC = %main::REINDEX_DATA;
        undef %main::REINDEX_DATA;

        sonos_musicdb_save();
        $main::UPDATEID{ShareIndexInProgress2} = 0;
        $main::MUSICUPDATE = $main::SONOS_UPDATENUM++;
        sonos_containers_del("A:");
        sonos_process_waiting("MUSIC");
        unlink glob $main::AACACHEDIR . "/*" if ($main::AACACHEDIR ne "");
    } else {
        add_timeout (time(), \&sonos_fetch_music_callback);
    }
}

###############################################################################
sub sonos_musicdb_save {
    $main::MUSIC{_info}->{ShareListUpdateID} = $main::UPDATEID{ShareListUpdateID};
    $main::MUSIC{_info}->{version} = $main::VERSION;

    {
        local $Data::Dumper::Purity = 1;
        Log (1, "Saving Music DB");
        open (DB, ">musicdb.pl");
        my $dumper = Data::Dumper->new( [\%main::MUSIC], [ qw( *main::MUSIC) ] );
        print DB $dumper->Dump();
        close DB;
        Log (1, "Finshed Saving Music DB");
    }

    delete $main::MUSIC{_info};
}
###############################################################################
sub sonos_musicdb_load {
    if ( -f "musicdb.pl") {
        Log (1, "Loading Music DB");
        do "./musicdb.pl";

	if ($@) {
            Log (0, "Error loading Music DB: $@");
        }

        $main::LASTUPDATE  = $main::SONOS_UPDATENUM;
        Log (1, "Finished Loading Music DB");

        # To make life easier, we always update the music index on new version install
        if ($main::MUSIC{_info}->{version} != $main::VERSION) {
            Log (1, "Old version of Music DB (". $main::MUSIC{_info}->{version}.") must rebuild for (" . $main::VERSION .")");
            undef %main::MUSIC;
        } else {
            $main::UPDATEID{ShareListUpdateID} = $main::MUSIC{_info}->{ShareListUpdateID};
            delete $main::MUSIC{_info};
        }
    }
}
###############################################################################
sub sonos_mkcontainer {
    my ($parent, $class, $title, $id, $icon, $content) = @_;

    my %data;

    $data{'upnp:class'}       = $class;
    $data{'dc:title'}         = $title;
    $data{parentID}           = $parent;
    $data{id}                 = $id;
    $data{'upnp:albumArtURI'} = $icon;
    $data{res}->{content}     = $content if (defined $content);

    push (@{$main::CONTAINERS{$parent}},  \%data);

    $main::ITEMS{$data{id}} = \%data;
}

###############################################################################
sub sonos_mkitem {
    my ($parent, $class, $title, $id, $content) = @_;

    $main::ITEMS{$id}->{"upnp:class"}   = $class;
    $main::ITEMS{$id}->{parentID}       = $parent;
    $main::ITEMS{$id}->{"dc:title"}     = $title;
    $main::ITEMS{$id}->{id}             = $id;
    $main::ITEMS{$id}->{res}->{content} = $content if (defined $content);
}
###############################################################################
sub sonos_containers_init {

    $main::MUSICUPDATE = $main::SONOS_UPDATENUM++;

    undef %main::CONTAINERS;

    sonos_mkcontainer("", "object.container", "Favorites", "FV:2", "tiles/favorites.svg");
    sonos_mkcontainer("", "object.container", "Artists", "A:ARTIST", "tiles/artists.svg");
    sonos_mkcontainer("", "object.container", "Albums", "A:ALBUM", "tiles/album.svg");
    sonos_mkcontainer("", "object.container", "Genres", "A:GENRE", "tiles/genre.svg");
    sonos_mkcontainer("", "object.container", "Composers", "A:COMPOSER", "tiles/composers.svg");
    #sonos_mkcontainer("", "object.container", "Imported Playlists", "A:PLAYLISTS", "tiles/playlist.svg");
    #sonos_mkcontainer("", "object.container", "Folders", "S:", "tiles/folder.svg");
    sonos_mkcontainer("", "object.container", "Radio", "R:0/0", "tiles/radio_logo.svg");
    # sonos_mkcontainer("", "object.container", "Line In", "AI:", "tiles/linein.svg");
    # sonos_mkcontainer("", "object.container", "Playlists", "SQ:", "tiles/sonos_playlists.svg");

    sonos_mkitem("", "object.container", "Music", "");
}
###############################################################################
sub sonos_containers_get {
    my ($what, $item) = @_;

    my ($zone) = split(",", $main::UPDATEID{ShareListUpdateID});
    if (!defined $zone) {
        my $foo = ();
        return $foo;
    }

    my $type = substr ($what, 0, index($what, ':'));

    if (defined $main::HOOK{"CONTAINER_$type"}) {
        sonos_process_hook("CONTAINER_$type", $what);
    }

    if (exists $main::CONTAINERS{$what}) {
        Log (2, "Using cache for $what");
    } elsif ($what eq "AI:") { # line-in
        $main::CONTAINERS{$what} = ();
        foreach my $zone (keys %main::ZONES) {
            my $linein =  upnp_content_dir_browse($zone, "AI:");

            if (defined $linein->[0]) {
                $linein->[0]->{id} .= "/" . $linein->[0]->{"dc:title"};
                push @{$main::CONTAINERS{$what}}, $linein->[0];
            }
        }
    } else {
        $main::CONTAINERS{$what} = upnp_content_dir_browse($zone, $what);
    }

    foreach my $item (@{$main::CONTAINERS{$what}}) {
        $main::ITEMS{$item->{id}} = $item;
    }
    return $main::CONTAINERS{$what};
}
###############################################################################
sub sonos_containers_del {
    my ($what) = @_;

    $main::MUSICUPDATE = $main::SONOS_UPDATENUM++;
    foreach my $key (keys %main::CONTAINERS) {
        next if (! ($key =~ /^$what/));
        foreach my $item (@{$main::CONTAINERS{$key}}) {
            delete $main::ITEMS{$item->{id}};
        }
        delete $main::CONTAINERS{$key};
    }

}
###############################################################################
sub sonos_prefsdb_save {
    {
        local $Data::Dumper::Purity = 1;
        Log (1, "Saving Prefs DB");
        open (DB, ">prefsdb.pl");
        my $dumper = Data::Dumper->new( [\%main::PREFS], [ qw( *main::PREFS) ] );
        print DB $dumper->Dump();
        close DB;
        Log (1, "Finshed Saving Prefs DB");
    }
}
###############################################################################
sub sonos_prefsdb_load {
    if ( -f "prefsdb.pl") {
        Log (1, "Loading Prefs DB");
        do "./prefsdb.pl";

	if ($@) {
            Log (0, "Error loading Prefs DB: $@");
        }
    }
}
###############################################################################
sub sonos_renew_subscriptions {
    Log (3, "invoked");
    foreach my $sub (keys %main::SUBSCRIPTIONS) {
        Log (3, "renew $sub");
        my $previousStart = $main::SUBSCRIPTIONS{$sub}->{_startTime};
        $main::SUBSCRIPTIONS{$sub}->renew();
        if($previousStart == $main::SUBSCRIPTIONS{$sub}->{_startTime}) {
            Log (1, "renew failed " . Dumper($@));
            # Renew failed, lets subscribe again
            my ($location, $name) = split (",", $sub);
            my $device = $main::DEVICE{$location};
            my $service = upnp_device_get_service($device, $name);
            $main::SUBSCRIPTIONS{"$location,$name"} = $service->subscribe(\&sonos_upnp_update);
        }
    }
    add_timeout(time()+$main::RENEW_SUB_TIME, \&sonos_renew_subscriptions);
}

###############################################################################
sub sonos_location_to_id {
    my ($location) = @_;

    foreach my $zone (keys %main::ZONES) {
        return $zone if ($main::ZONES{$zone}->{Location} eq $location);
    }
    return undef;
}

###############################################################################
sub sonos_upnp_update {
    my ($service, %properties) = @_;

    Log (2, "Event received for service=" . $service->{BASE} . " id = " . $service->serviceId);
    Log(4, Dumper(\%properties));

    # Save off the zone names
    if ($service->serviceId =~ /serviceId:ZoneGroupTopology/) {
        foreach my $key (keys %properties) {
            if ($key eq "ZoneGroupState") {
                my $tree = XMLin(decode_entities($properties{$key}), 
                        forcearray => ["ZoneGroup", "ZoneGroupMember"]);
                Log(4, "ZoneGroupTopology " . Dumper($tree));
                foreach my $group (@{$tree->{ZoneGroup}}) {
                    my %zonegroup = %{$group};
                    my $coordinator = $zonegroup{Coordinator};
                    my @members = @{$zonegroup{ZoneGroupMember}};
                    $main::ZONES{$coordinator}->{Members} = [];

                    foreach my $member (@members) {
                        my $zkey = $member->{UUID};
                        foreach my $mkey (keys %{$member}) {
                            $main::ZONES{$zkey}->{$mkey} = $member->{$mkey};
                        }
                        $main::ZONES{$zkey}->{Coordinator} = $coordinator;
                        push @{ $main::ZONES{$coordinator}->{Members} }, $zkey;

                        my @ip = split(/\//, $member->{Location});
                        $main::ZONES{$zkey}->{IPPORT} = $ip[2];
                        $main::ZONES{$zkey}->{AV}->{LASTUPDATE} = 1 if (!defined $main::ZONES{$zkey}->{AV}->{LASTUPDATE});
                        $main::ZONES{$zkey}->{RENDER}->{LASTUPDATE} = 1 if (!defined $main::ZONES{$zkey}->{RENDER}->{LASTUPDATE});
                        $main::ZONES{$zkey}->{AV}->{CurrentTrackMetaData} = "" if (!defined $main::ZONES{$zkey}->{AV}->{CurrentTrackMetaData});
                        $main::QUEUEUPDATE{$zkey} = 1 if (!defined $main::QUEUEUPDATE{$zkey});
                    }
                }
                $main::LASTUPDATE  = $main::SONOS_UPDATENUM;
                $main::ZONESUPDATE = $main::SONOS_UPDATENUM++;

                sonos_process_waiting("ZONES");
            } elsif ($key eq "ThirdPartyMediaServers") {
                my $tree = XMLin(decode_entities($properties{$key}), forcearray => ["Service"]);
                for my $item ( @{ $tree->{Service} } ) {
                    if($item->{UDN} =~ "SA_RINCON1_") { #Rhapsody
                        Log(2, "Adding Rhapsody Subscription");
                        $main::SERVICES{Rhapsody} = $item;
                    } elsif($item->{UDN} =~ "SA_RINCON4_") { #PANDORA
                        Log(2, "Adding Pandora Subscription");
                        $main::SERVICES{Pandora} = $item;
                        
                    } elsif($item->{UDN} =~ "SA_RINCON6_") { #SIRIUS
                        Log(2, "Adding Sirius Subscription");
                        $main::SERVICES{Sirius} = $item;
                    } 
                }
                sonos_process_waiting("SERVICES");
            } else {
                Log(4, "$key " . Dumper($properties{$key}));
            }
        }
    }

    Log(4, "Parsed ZoneGroupTopology " . Dumper(\%main::ZONES));

    my $zone = sonos_location_to_id($service->{BASE});

    # Save off the current status
    if ($service->serviceId =~ /serviceId:RenderingControl/) {
        if (decode_entities($properties{LastChange}) eq "") {
            Log(3, "Unknown RenderingControl " . Dumper(\%properties));
            return;
        }
        my $tree = XMLin(decode_entities($properties{LastChange}), 
                forcearray => ["ZoneGroup"], 
                keyattr=>{"Volume"   => "channel",
                          "Mute"     => "channel",
                          "Loudness" => "channel"});
        Log(4, "RenderingControl " . Dumper($tree));
        foreach my $key ("Volume", "Treble", "Bass", "Mute", "Loudness") {
            if ($tree->{InstanceID}->{$key}) {
                $main::ZONES{$zone}->{RENDER}->{$key} = $tree->{InstanceID}->{$key};
                $main::LASTUPDATE                 = $main::SONOS_UPDATENUM;
                $main::ZONES{$zone}->{RENDER}->{LASTUPDATE} = $main::SONOS_UPDATENUM++;
            }
        }

        sonos_process_waiting("RENDER", $zone);

        return;
    }

    if ($service->serviceId =~ /serviceId:AVTransport/) {
        if (decode_entities($properties{LastChange}) eq "") {
            Log(3, "Unknown AVTransport " . Dumper(\%properties));
            return;
        }
        my $tree = XMLin(decode_entities($properties{LastChange}));
        Log(4, "AVTransport " . Dumper($tree));

        foreach my $key ("CurrentTrackMetaData", "CurrentPlayMode", "NumberOfTracks", "CurrentTrack", "TransportState", "AVTransportURIMetaData", "AVTransportURI", "r:NextTrackMetaData", "CurrentTrackDuration") {
            if ($tree->{InstanceID}->{$key}) {
                $main::LASTUPDATE             = $main::SONOS_UPDATENUM;
                $main::ZONES{$zone}->{AV}->{LASTUPDATE} = $main::SONOS_UPDATENUM++;
                if ($tree->{InstanceID}->{$key}->{val} =~ /^&lt;/) {
                    $tree->{InstanceID}->{$key}->{val} = decode_entities($tree->{InstanceID}->{$key}->{val});
                }
                if ($tree->{InstanceID}->{$key}->{val} =~ /^</) {
                    $main::ZONES{$zone}->{AV}->{$key} = \%{XMLin($tree->{InstanceID}->{$key}->{val})};
                } else {
                    $main::ZONES{$zone}->{AV}->{$key} = $tree->{InstanceID}->{$key}->{val};
                }
            }  
        }

        sonos_process_waiting("AV", $zone);
        return;
    }


    if ($service->serviceId =~ /serviceId:ContentDirectory/) {
        Log(4, "ContentDirectory " . Dumper(\%properties));

        if (defined $properties{ContainerUpdateIDs} && $properties{ContainerUpdateIDs} =~ /AI:/) {
            sonos_containers_del("AI:");
        }

        if (!defined $main::ZONES{$zone}->{QUEUE} || $properties{ContainerUpdateIDs} =~ /Q:0/) {
            Log (2, "Refetching Q for $main::ZONES{$zone}->{ZoneName} updateid $properties{ContainerUpdateIDs}");
            $main::ZONES{$zone}->{QUEUE} = upnp_content_dir_browse($zone, "Q:0");
            $main::LASTUPDATE = $main::SONOS_UPDATENUM;
            $main::QUEUEUPDATE{$zone} = $main::SONOS_UPDATENUM++;
            sonos_process_waiting("QUEUE", $zone);
        }

        if (defined $properties{ShareIndexInProgress}) {
            $main::UPDATEID{ShareIndexInProgress} = $properties{ShareIndexInProgress};
        }

        if (defined $properties{MasterRadioUpdateID} && ($properties{MasterRadioUpdateID} ne $main::UPDATEID{MasterRadioUpdateID})) {
            $main::UPDATEID{MasterRadioUpdateID} = $properties{MasterRadioUpdateID};
            sonos_containers_del("R:0/0");
        }

        if (defined $properties{SavedQueuesUpdateID} && $properties{SavedQueuesUpdateID} ne $main::UPDATEID{SavedQueuesUpdateID}) {
            $main::UPDATEID{SavedQueuesUpdateID} = $properties{SavedQueuesUpdateID};
            sonos_containers_del("SQ:");
        }

        if (defined $properties{ShareListUpdateID} && $properties{ShareListUpdateID} ne $main::UPDATEID{ShareListUpdateID}) {
            $main::UPDATEID{ShareListUpdateID} = $properties{ShareListUpdateID};
            Log (2, "Refetching Index, update id $properties{ShareListUpdateID}");
            add_timeout (time(), \&sonos_fetch_music);
        }
        return;
    }


    while (my ($key, $val) = each %properties) {
        if ($val =~ /&lt/) {
            my $d = decode_entities($val);
            my $tree = XMLin($d, forcearray => ["ZoneGroup"], keyattr=>{"ZoneGroup" => "ID"});
            Log(3, "Property ${key}'s value is " . Dumper($tree));
        } else {
            Log(3, "Property ${key}'s value is " . $val);
        }
    }
}
###############################################################################
sub sonos_music_isfav {
    my ($mpath) = @_;
    return $mpath =~ /^FV:/;
}

###############################################################################
sub sonos_music_realpath {
    my ($mpath) = @_;

    my $entry = sonos_music_entry($mpath);
    return $mpath if (!defined $entry);
    return $mpath if (!$entry->{'r:resMD'});
    my $meta = XMLin($entry->{'r:resMD'});
    return $mpath if (!$meta->{item}->{id});
    return $meta->{item}->{id};
}
###############################################################################
sub sonos_music_class {
    my ($mpath) = @_;

    my $entry = sonos_music_entry($mpath);
    return undef if (!defined $entry);
    return $entry->{"upnp:class"};
}
###############################################################################
sub sonos_music_entry {
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

    $mpath = sonos_music_realpath($mpath);

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
sub sonos_add_hook {
    my $what = shift @_;
    my $cb   = shift @_;

    push @{$main::HOOK{$what}}, [$cb, @_];
}
###############################################################################
sub sonos_process_hook {
    my ($what, @other) = @_;

    return undef if (!defined $main::HOOK{$what});

    my @hooks = @{$main::HOOK{$what}}; 

    while ($#hooks >= 0) {
        my($callback, @args) = @{shift @hooks};
        my $out = &$callback($what, @other, @args);
        return $out if (defined $out);
    }
    return undef;
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
# UPNP
###############################################################################

###############################################################################
sub upnp_device_get_service {
    my ($device, $name) = @_;

    my $service = $device->getService($name);
    return $service if ($service);

    for my $child ($device->children) {
        $service = $child->getService($name);
        return $service if ($service);
    }
    return undef;
}

###############################################################################
sub upnp_zone_get_service {
    my ($zone, $name) = @_;

    if (! exists $main::ZONES{$zone} || 
        ! defined $main::ZONES{$zone}->{Location} || 
        ! defined $main::DEVICE{$main::ZONES{$zone}->{Location}}) {
        main::Log(0, "Zone '$zone' not found");
        return undef;
    }

    return upnp_device_get_service($main::DEVICE{$main::ZONES{$zone}->{Location}}, $name);
}

###############################################################################
sub upnp_content_dir_create_object {
    my ($zone, $containerid, $elements) = @_;
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    return undef if (! defined $contentDir);
    my $contentDirProxy = $contentDir->controlProxy; 
    my $result = $contentDirProxy->CreateObject($containerid, $elements);
    return $result;
}
###############################################################################
sub upnp_content_dir_destroy_object {
    my ($zone, $objectid) = @_;
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    return undef if (! defined $contentDir);
    my $contentDirProxy = $contentDir->controlProxy; 
    my $result = $contentDirProxy->DestroyObject($objectid);
    return $result;
}
###############################################################################
sub upnp_content_dir_browse {
    my ($zone, $objectid, $type) = @_;

    $type = 'BrowseDirectChildren' if (!defined $type);

    Log(4, "zone: $zone objectid: $objectid type: $type");

    my $start = 0;
    my @data = ();
    my $result;

    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    return undef if (! defined $contentDir);
    my $contentDirProxy = $contentDir->controlProxy; 

    do {
        $result = $contentDirProxy->Browse($objectid, $type, 
                                           'dc:title,res,dc:creator,upnp:artist,upnp:album', 
                                           $start, 2000, "");

        return undef if (!$result->isSuccessful);

        $start += $result->getValue("NumberReturned");

        my $results = $result->getValue("Result");
        my $tree = XMLin($results, forcearray => ["item", "container"], keyattr=>{"item" => "ID"});

        push(@data, @{$tree->{item}}) if (defined $tree->{item});
        push(@data, @{$tree->{container}}) if (defined $tree->{container});
    } while ($start < $result->getValue("TotalMatches"));

    return \@data;
}

###############################################################################
sub upnp_content_dir_delete {
    my ($zone, $objectid) = @_;

    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    my $contentDirProxy = $contentDir->controlProxy; 

    $contentDirProxy->DestroyObject($objectid);
}

###############################################################################
sub upnp_content_dir_refresh_share_index {
    my ($zone) = split(",", $main::UPDATEID{ShareListUpdateID});
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");

    if (! defined $contentDir) {
        if ($zone eq "") {
            Log(0, "Main zone not found yet, will retry.  Windows XP *WILL* require rerunning SonosWeb after selecting 'Unblock' in the Windows Security Alert.");
        } else {
            Log(1, "$zone not available, will retry");
        }
        add_timeout (time()+5, \&upnp_content_dir_refresh_share_index);
        return
    }
    my $contentDir = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:ContentDirectory:1");
    my $contentDirProxy = $contentDir->controlProxy; 
    $contentDirProxy->RefreshShareIndex();
}

###############################################################################
sub upnp_avtransport_remove_track {
    my ($zone, $objectid) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->RemoveTrackFromQueue("0", $objectid);
    return;
}
###############################################################################
sub upnp_avtransport_play {
    my ($zone) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->Play("0", "1");
    return $result;
}
###############################################################################
sub upnp_avtransport_seek {
    my ($zone,$queue) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    $queue =~ s,^.*/,,;

    my $result = $avTransportProxy->Seek("0", "TRACK_NR", $queue);
    return $result;
}
###############################################################################
sub upnp_render_mute {
    my ($zone,$on) = @_;

    if (!defined $on) {
        return $main::ZONES{$zone}->{RENDER}->{Mute}->{Master}->{val};
    }

    my $render = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:RenderingControl:1");
    my $renderProxy = $render->controlProxy;
    my $result = $renderProxy->SetMute("0", "Master", $on);
    $main::ZONES{$zone}->{RENDER}->{Mute}->{Master}->{val} = $on if ($result->isSuccessful);
    return $on;
}
###############################################################################
sub upnp_render_volume_change {
    my ($volzone,$change) = @_;

    foreach my $zone (keys %main::ZONES) {
        if ($volzone eq $main::ZONES{$zone}->{Coordinator}) {
            my $vol = $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val} + $change;
            upnp_render_volume($zone,$vol);
        }
    }
}
###############################################################################
sub upnp_render_volume {
    my ($zone,$vol) = @_;

    if (!defined $vol) {
        return $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val};
    }

    $vol = 100 if ($vol > 100);
    $vol = 0 if ($vol < 0);

    my $render = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:RenderingControl:1");
    my $renderProxy = $render->controlProxy;
    my $result = $renderProxy->SetVolume("0", "Master", $vol);
    $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val} = $vol if ($result->isSuccessful);
    return $vol;
}
###############################################################################
sub upnp_avtransport_action {
    my ($zone,$action) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->$action("0");
    return $result;
}
###############################################################################
sub upnp_avtransport_repeat {
    my ($zone, $repeat) = @_;

    my $str = $main::ZONES{$zone}->{AV}->{CurrentPlayMode};

    if (!defined $repeat) {
        return 0 if ($str eq "NORMAL" || $str eq "SHUFFLE");
        return 1;
    }

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    if ($str eq "NORMAL") {
        $str = "REPEAT_ALL" if ($repeat);
    } elsif ($str eq "REPEAT_ALL") {
        $str = "NORMAL" if (!$repeat);
    } elsif ($str eq "SHUFFLE_NOREPEAT") {
        $str = "SHUFFLE" if ($repeat);
    } elsif ($str eq "SHUFFLE") {
        $str = "SHUFFLE_NOREPEAT" if (!$repeat);
    }
    my $result = $avTransportProxy->SetPlayMode("0", $str);
    $main::ZONES{$zone}->{AV}->{CurrentPlayMode} = $str if ($result->isSuccessful);
    return $repeat;
}
###############################################################################
sub upnp_avtransport_shuffle {
    my ($zone, $shuffle) = @_;

    my $str = $main::ZONES{$zone}->{AV}->{CurrentPlayMode};

    if (!defined $shuffle) {
        return 0 if ($str eq "NORMAL" || $str eq "REPEAT_ALL");
        return 1;
    }

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    if ($str eq "NORMAL") {
        $str = "SHUFFLE_NOREPEAT" if ($shuffle);
    } elsif ($str eq "REPEAT_ALL") {
        $str = "SHUFFLE" if ($shuffle);
    } elsif ($str eq "SHUFFLE_NOREPEAT") {
        $str = "NORMAL" if (!$shuffle);
    } elsif ($str eq "SHUFFLE") {
        $str = "REPEAT_ALL" if (!$shuffle);
    }

    my $result = $avTransportProxy->SetPlayMode("0", $str);
    $main::ZONES{$zone}->{AV}->{CurrentPlayMode} = $str if ($result->isSuccessful);
    return $shuffle;
}
###############################################################################
sub upnp_avtransport_set_uri {
    my ($zone, $uri, $metadata) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;
    my $result = $avTransportProxy->SetAVTransportURI(0, $uri, $metadata);
    return $result;
}

###############################################################################
sub upnp_avtransport_add_uri {
    my ($zone, $uri, $metadata, $queueSlot) = @_;

    Log (2, "zone=$zone uri=$uri metadata=$metadata");

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;

    my $result = $avTransportProxy->AddURIToQueue(0, $uri, $metadata, $queueSlot);
    return $result;
}

###############################################################################
sub upnp_avtransport_standalone_coordinator {
    my ($zone) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;
    my $result = $avTransportProxy->BecomeCoordinatorOfStandaloneGroup(0);
    return $result;
}

###############################################################################
sub upnp_avtransport_save {
    my ($zone, $name) = @_;

    my $avTransport = upnp_zone_get_service($zone, "urn:schemas-upnp-org:service:AVTransport:1");
    my $avTransportProxy = $avTransport->controlProxy;
    my $result = $avTransportProxy->SaveQueue(0, $name, "");
    return $result;
}
###############################################################################
sub upnp_search_cb {
    my ($search, $device, $action) = @_;
    if ($action eq 'deviceAdded') {
        Log(2, "Added name: " . $device->friendlyName . " " . $device->{UDN} . " type: " . $device->deviceType());
        Log(2, %$device);


#        next if ($device->{LOCATION} !~ /xml\/zone_player.xml/);
        $main::DEVICE{$device->{LOCATION}} = $device;

#                             urn:schemas-upnp-org:service:DeviceProperties:1

        foreach my $name (qw(urn:schemas-upnp-org:service:ZoneGroupTopology:1 
                             urn:schemas-upnp-org:service:ContentDirectory:1 
                             urn:schemas-upnp-org:service:AVTransport:1 
                             urn:schemas-upnp-org:service:RenderingControl:1)) {
            my $service = upnp_device_get_service($device, $name);
            $main::SUBSCRIPTIONS{"$device->{LOCATION},$name"} = $service->subscribe(\&sonos_upnp_update);
        }
    }
    elsif ($action eq 'deviceRemoved') {
        Log(1, "Removed name:" . $device->friendlyName) . " zone=" . substr($device->{UDN}, 5);
        delete $main::ZONES{substr($device->{UDN}, 5)};
    } else {
        Log(1, "Unknown action name:" . $device->friendlyName);
    }
}
###############################################################################
# HTTP
###############################################################################

%main::HTTP_HANDLERS   = ();

###############################################################################
sub http_register_handler  {
    my ($path, $callback) = @_;

    $main::HTTP_HANDLERS{$path} = $callback;
}

###############################################################################
sub http_albumart_request {
    my ($c, $r) = @_;

    my $uri = $r->uri;
    my %qf = $uri->query_form;
    my $sha = sha256_hex($uri);
    my $response;


    delete $qf{zone} if (exists $qf{zone} && !exists $main::ZONES{$qf{zone}});

    if (($main::AACACHEDIR ne "") and ( -r $main::AACACHEDIR . "/" . $sha)) {
        my $text = read_file($main::AACACHEDIR . "/" . $sha);
        $response = HTTP::Response->parse($text)
    } else {
        wakeup_nas();

        my @zones = keys (%main::ZONES);
        my $zone = $main::ZONES{$zones[0]}->{Coordinator};
        my $ipport = $main::ZONES{$zone}->{IPPORT};

        # Get the album art given the mpath instead of the albumart path
        if ($uri->path eq "/getAA") {
            my $mpath = decode("UTF-8", $qf{mpath});
            my @parts = split("/", $mpath);

            if ($#parts == 2) {
                $uri = "/getaa?uri=" . (values %{$main::MUSIC{$parts[1]}{$parts[2]}} ) [0]->{res}->{content};
            } elsif ($#parts == 3) {
                $uri = "/getaa?uri=" . $main::MUSIC{$parts[1]}{$parts[2]}{$parts[3]}->{res}->{content};
            } else {
                $c->send_error(HTTP::Status::RC_NOT_FOUND);
                $c->force_last_request;
            }
        }

        my $request = "http://$ipport" . $uri;
        $response = $main::useragent->get($request);

        if ($response->is_success() and ($main::AACACHEDIR ne "")) {
            write_file($main::AACACHEDIR . "/" . $sha, $response->as_string());
        }
    }

    Log(3, "Sending response to " . $r->url);
    $c->send_response($response);
    $c->force_last_request;
}
###############################################################################
sub http_base_url {
    my ($r) = @_;

    my $baseurl;

    if (!defined $r || ! $r->header("host")) {
        $baseurl = "http://". UPnP::Common::getLocalIP().":".$main::HTTP_PORT;
    } else {
        $baseurl = "http://".$r->header("host");
    }

    return $baseurl;
}
###############################################################################
sub http_check_password {
my ($c, $r) = @_;

    if ($main::PASSWORD ne "") {
        my $auth = $r->header("Authorization");
        my $senderr = 1;
        if (defined $auth && $auth =~ /Basic +(.*)/) {
            my ($name, $pass) = split(/:/, decode_base64($1));
            $senderr = 0 if ($main::PASSWORD eq $pass);
        }

        if ($senderr) {
            my $response = HTTP::Response->new(401, undef, ["WWW-Authenticate" => "Basic realm=\"SonosWeb\""], "Please provide correct password");
            Log(3, "Sending response to " . $r->url);
            $c->send_response($response);
            $c->force_last_request;
            return 1;
        }
    }

    return 0;
}
###############################################################################
sub http_handle_request {
    my ($c, $r) = @_;


    # No r, just return
    if (!$r || !$r->uri) {
        Log (1, "Missing Request");
        return;
    }

    my $uri = $r->uri;

    my $path = $uri->path;
    my $baseurl = http_base_url($r);

    if (($path eq "/") || ($path =~ /\.\./)) {
        $c->send_redirect("$baseurl/$main::DEFAULT");
        $c->force_last_request;
        return;
    }

    my %qf = $uri->query_form;
    delete $qf{zone} if (exists $qf{zone} && !exists $main::ZONES{$qf{zone}});
    

    Log (1, "URI: $uri");

    if ($main::HTTP_HANDLERS{$path}) {
        my $callback = $main::HTTP_HANDLERS{$path};
        &$callback($c, $r);
        return;
    }

    # Find where on disk
    my $diskpath;
    my $tmplhook;
    if (-e "html/$path") {
        $diskpath = "html$path";
    } else {
        my @parts = split("/", $path);
        my $plugin = $parts[1];
        splice(@parts, 0, 2);
        my $restpath = join("/", @parts);
        if ($main::PLUGINS{$plugin} && $main::PLUGINS{$plugin}->{html} && 
            -e $main::PLUGINS{$plugin}->{html} . $restpath) {
            $diskpath = $main::PLUGINS{$plugin}->{html} . $restpath;
            $tmplhook = $main::PLUGINS{$plugin}->{tmplhook};
        }
    }

    # File doesn't exist
    if ( ! $diskpath) {
        $c->send_error(HTTP::Status::RC_NOT_FOUND);
        $c->force_last_request;
        return;
    }

    # File is a directory, redirect for the browser
    if (-d $diskpath) {
        if ($path =~ /\/$/) {
            $c->send_redirect($baseurl . $path . "index.html");
        } else {
            $c->send_redirect($baseurl . $path . "/index.html");
        }
        $c->force_last_request;
        return;
    }

    # File isn't HTML/XML/JSON, just send it back raw
    if (!($path =~ /\.html/) && !($path =~ /\.xml/) && !($path =~ /\.json/)) {
        $c->send_file_response($diskpath);
        $c->force_last_request;
        return;
    }

    # 0 - not handled, 1 - handled send reply, >= 2 - handled routine will send reply
    my $response = 0;

    if (exists $qf{action}) {
        return if (http_check_password ($c, $r));

        if (exists $qf{zone}) {
            $response = http_handle_zone_action($c, $r, $path);
        }
        if (! $response) {
            $response = http_handle_action($c, $r, $path);
        }
    }

    if ($qf{NoWait}) {
        $response = 1;
    }

    if ($response == 2) {
        sonos_add_waiting("AV", "*", \&http_send_tmpl_response, $c, $r, $diskpath, $tmplhook);
    } elsif ($response == 3) {
        sonos_add_waiting("RENDER", "*", \&http_send_tmpl_response, $c, $r, $diskpath, $tmplhook);
    } elsif ($response == 4) {
        sonos_add_waiting("QUEUE", "*", \&http_send_tmpl_response, $c, $r, $diskpath, $tmplhook);
    } elsif ($response == 5) {
        sonos_add_waiting("*", "*", \&http_send_tmpl_response, $c, $r, $diskpath, $tmplhook);
    } else {
        http_send_tmpl_response("*", "*", $c, $r, $diskpath, $tmplhook);
    }

}

###############################################################################
sub http_handle_zone_action {
my ($c, $r, $path) = @_;

    my %qf = $r->uri->query_form;
    delete $qf{zone} if (exists $qf{zone} && !exists $main::ZONES{$qf{zone}});
    my $mpath = decode("UTF-8", $qf{mpath});

    my $zone = $qf{zone};
    if ($qf{action} eq "Remove") {
        upnp_avtransport_remove_track($zone, $qf{queue});
        return 4;
    } elsif ($qf{action} eq "RemoveAll") {
        upnp_avtransport_action($zone, "RemoveAllTracksFromQueue");
        return 4;
    } elsif ($qf{action} eq "Play") {
        if ($main::ZONES{$zone}->{AV}->{TransportState} eq "PLAYING") {
            return 1;
        } else {
            upnp_avtransport_play($zone);
            return 2;
        }
    } elsif ($qf{action} eq "Pause") {
        if ($main::ZONES{$zone}->{AV}->{TransportState} eq "PAUSED_PLAYBACK") {
            return 1;
        } else {
            upnp_avtransport_action($zone, $qf{action});
            return 2;
        }
    } elsif ($qf{action} eq "Stop") {
        if ($main::ZONES{$zone}->{AV}->{TransportState} eq "STOPPED") {
            return 1;
        } else {
            upnp_avtransport_action($zone, $qf{action});
            return 2;
        }
    } elsif ($qf{action} =~ /(Next|Previous)/) {
        upnp_avtransport_action($zone, $qf{action});
        return 2;
    } elsif ($qf{action} eq "ShuffleOn") {
        upnp_avtransport_shuffle($zone, 1);
        return 1;
    } elsif ($qf{action} eq "ShuffleOff") {
        upnp_avtransport_shuffle($zone, 0);
        return 1;
    } elsif ($qf{action} eq "RepeatOn") {
        upnp_avtransport_repeat($zone, 1);
        return 1;
    } elsif ($qf{action} eq "RepeatOff") {
        upnp_avtransport_repeat($zone, 0);
        return 1;
    } elsif ($qf{action} eq "Seek") {
        if (! ($main::ZONES{$zone}->{AV}->{AVTransportURI} =~ /queue/)) {
            sonos_avtransport_set_queue($zone);
        }
        upnp_avtransport_seek($zone, $qf{queue});
        return 2;
    } elsif ($qf{action} eq "MuteOn") {
        upnp_render_mute($zone, 1);
        return 3;
    } elsif ($qf{action} eq "MuteOff") {
        upnp_render_mute($zone, 0);
        return 3;
    } elsif ($qf{action} eq "MuchSofter") {
        upnp_render_volume_change($zone, -5);
        return 3;
    } elsif ($qf{action} eq "Softer") {
        upnp_render_volume_change($zone, -1);
        return 3;
    } elsif ($qf{action} eq "Louder") {
        upnp_render_volume_change($zone, +1);
        return 3;
    } elsif ($qf{action} eq "MuchLouder") {
        upnp_render_volume_change($zone, +5);
        return 3;
    } elsif ($qf{action} eq "SetVolume") {
        upnp_render_volume($zone, $qf{volume});
        return 3;
    } elsif ($qf{action} eq "Save") {
        upnp_avtransport_save($zone, $qf{savename});
        return 0;
    } elsif ($qf{action} eq "AddMusic") {
        my $class = sonos_music_class($mpath);
        if (sonos_is_radio($mpath)) {
            sonos_avtransport_set_radio($zone, $mpath);
            return 2;
        } elsif ($class eq "object.item.audioItem") {
            sonos_avtransport_set_linein($zone, $mpath);
            return 2;
        } else {
            sonos_avtransport_add($zone, $mpath);
            return 4;
        }
    } elsif ($qf{action} eq "DeleteMusic") {
        if (sonos_music_class($mpath) eq "object.container.playlist") {
            my $entry = sonos_music_entry($mpath);
            upnp_content_dir_delete($zone, $entry->{id});
        }
        return 0;
    } elsif ($qf{action} eq "PlayMusic") {
        my $class = sonos_music_class($mpath);
        if (sonos_is_radio($mpath)) {
            sonos_avtransport_set_radio($zone, $mpath);
        } elsif ($class eq "object.item.audioItem") {
            sonos_avtransport_set_linein($zone, $mpath);
        } else {
            if (! ($main::ZONES{$zone}->{AV}->{AVTransportURI} =~ /queue/)) {
                sonos_avtransport_set_queue($zone);
            }
            upnp_avtransport_action($zone, "RemoveAllTracksFromQueue");
            sonos_avtransport_add($zone, $mpath);
            upnp_avtransport_play($zone);
        }

        return 4;
    } elsif ($qf{action} eq "LinkAll") {
        sonos_link_all_zones($zone);
        return 2;
    } elsif ($qf{action} eq "Unlink") {
        sonos_unlink_zone($qf{link});
        return 2;
    } elsif ($qf{action} eq "Link") {
        sonos_link_zone($zone, $qf{link});
    } else {
        return 0;
    }
    return 1;
}

###############################################################################
sub http_handle_action {
my ($c, $r, $path) = @_;

    my %qf = $r->uri->query_form;
    delete $qf{zone} if (exists $qf{zone} && !exists $main::ZONES{$qf{zone}});

    if ($qf{action} eq "ReIndex") {
        sonos_reindex();
    } elsif ($qf{action} eq "Unlink") {
        sonos_unlink_zone($qf{link});
    } elsif ($qf{action} eq "Wait" && $qf{lastupdate}) {
        if ($main::LASTUPDATE > $qf{lastupdate}) {
            return 1;
        } else {
            return 5;
        }
    } else {
        return 0;
    }
    return 1;
}

###############################################################################
sub http_build_zone_data {
my ($zone, $updatenum, $active_zone) = @_;
    my %activedata;

    $activedata{HAS_ACTIVE_ZONE}  = int(defined $active_zone);
    $activedata{ACTIVE_ZONE}      = enc($main::ZONES{$zone}->{ZoneName});
    $activedata{ACTIVE_ZONEID}    = uri_escape($zone); 
    $activedata{ACTIVE_VOLUME}    = int($main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val});
    $activedata{ZONE_ACTIVE}      = int($zone eq $active_zone);

    my $lastupdate;
    if ($main::ZONES{$zone}->{RENDER}->{LASTUPDATE} > $main::ZONES{$zone}->{AV}->{LASTUPDATE}) {
        $lastupdate = $main::ZONES{$zone}->{RENDER}->{LASTUPDATE};
    } else {
        $lastupdate = $main::ZONES{$zone}->{AV}->{LASTUPDATE};
    }

    $activedata{ACTIVE_LASTUPDATE} = $lastupdate;
    $activedata{ACTIVE_UPDATED}    = ($lastupdate > $updatenum);

    if ($main::ZONES{$zone}->{RENDER}->{Mute}->{Master}->{val}) {
        $activedata{ACTIVE_MUTED} = 1;
    } else {
        $activedata{ACTIVE_MUTED} = 0;
    }


    my $curtrack     = $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData};
    my $curtransport = $main::ZONES{$zone}->{AV}->{AVTransportURIMetaData};

    $activedata{ACTIVE_NAME}      = "";
    $activedata{ACTIVE_ARTIST}    = "";
    $activedata{ACTIVE_ALBUM}     = "";
    $activedata{ACTIVE_ISSONG}    = 1;
    $activedata{ACTIVE_ISRADIO}   = 0;
    $activedata{ACTIVE_TRACK_NUM} = 0;
    $activedata{ACTIVE_TRACK_TOT} = 0;
    $activedata{ACTIVE_TRACK_TOT_0} = 0;
    $activedata{ACTIVE_TRACK_TOT_1} = 0;
    $activedata{ACTIVE_TRACK_TOT_GT_1} = 0;
    $activedata{ACTIVE_MODE}      = 0;
    $activedata{ACTIVE_PAUSED}    = 0;
    $activedata{ACTIVE_STOPPED}   = 0;
    $activedata{ACTIVE_PLAYING}   = 0;
    $activedata{ACTIVE_SHUFFLE}   = 0;
    $activedata{ACTIVE_REPEAT}    = 0;
    $activedata{ACTIVE_LENGTH}    = 0;
    $activedata{ACTIVE_ALBUMART}  = "";
    $activedata{ACTIVE_CONTENT}   = "";

    if ($curtrack) {
        if ($curtrack->{item}->{res}{content}) {
            $activedata{ACTIVE_CONTENT}   = $curtrack->{item}->{res}{content};
        }

        if ($curtrack->{item}->{"upnp:albumArtURI"}) {
            $activedata{ACTIVE_ALBUMART}  = $curtrack->{item}->{"upnp:albumArtURI"};
        }

        if ($curtransport && $curtransport->{item}->{"upnp:class"} eq "object.item.audioItem.audioBroadcast") {
            if (!ref($curtrack->{item}->{"r:streamContent"})) {
                $activedata{ACTIVE_NAME}  = enc($curtrack->{item}->{"r:streamContent"});
            }

            if (enc($curtrack->{item}->{"dc:creator"}) eq "") {
                $activedata{ACTIVE_ALBUM}     = enc($curtransport->{item}->{"dc:title"});
            } else{
                $activedata{ACTIVE_NAME}      = enc($curtrack->{item}->{"dc:title"});
                $activedata{ACTIVE_ARTIST}    = enc($curtrack->{item}->{"dc:creator"});
                $activedata{ACTIVE_ALBUM}     = enc($curtrack->{item}->{"upnp:album"});
                $activedata{ACTIVE_TRACK_NUM} = -1;
                $activedata{ACTIVE_TRACK_TOT} = $curtransport->{item}->{"dc:title"} . " \/";
            }

            $activedata{ACTIVE_ISSONG}    = 0;
            $activedata{ACTIVE_ISRADIO}   = 1;
        } else {

            $activedata{ACTIVE_NAME}      = enc($curtrack->{item}->{"dc:title"});
            $activedata{ACTIVE_ARTIST}    = enc($curtrack->{item}->{"dc:creator"});
            $activedata{ACTIVE_ALBUM}     = enc($curtrack->{item}->{"upnp:album"});
            $activedata{ACTIVE_TRACK_NUM} = $main::ZONES{$zone}->{AV}->{CurrentTrack};
            $activedata{ACTIVE_TRACK_TOT} = $main::ZONES{$zone}->{AV}->{NumberOfTracks};
            $activedata{ACTIVE_TRACK_TOT_0} = ($main::ZONES{$zone}->{AV}->{NumberOfTracks} == 0);
            $activedata{ACTIVE_TRACK_TOT_1} = ($main::ZONES{$zone}->{AV}->{NumberOfTracks} == 1);
            $activedata{ACTIVE_TRACK_TOT_GT_1} = ($main::ZONES{$zone}->{AV}->{NumberOfTracks} > 1);
        }
        if ($main::ZONES{$zone}->{AV}->{TransportState} eq "PAUSED_PLAYBACK") {
            $activedata{ACTIVE_MODE}      = 2;
            $activedata{ACTIVE_PAUSED}    = 1;
        } elsif ($main::ZONES{$zone}->{AV}->{TransportState} eq "STOPPED"){
            $activedata{ACTIVE_MODE}      = 0;
            $activedata{ACTIVE_STOPPED}   = 1;
        } else {
            $activedata{ACTIVE_MODE}      = 1;
            $activedata{ACTIVE_PLAYING}   = 1;
        }


        if ($main::ZONES{$zone}->{AV}->{CurrentPlayMode} eq "NORMAL") {
        } elsif ($main::ZONES{$zone}->{AV}->{CurrentPlayMode} eq "REPEAT_ALL") {
            $activedata{ACTIVE_REPEAT}    = 1;
        } elsif ($main::ZONES{$zone}->{AV}->{CurrentPlayMode} eq "SHUFFLE_NOREPEAT") {
            $activedata{ACTIVE_SHUFFLE}   = 1;
        } elsif ($main::ZONES{$zone}->{AV}->{CurrentPlayMode} eq "SHUFFLE") {
            $activedata{ACTIVE_SHUFFLE}   = 1;
            $activedata{ACTIVE_REPEAT}    = 1;
        }
    }


    if ($main::ZONES{$zone}->{AV}->{CurrentTrackDuration}) {
        my @parts = split(":", $main::ZONES{$zone}->{AV}->{CurrentTrackDuration});
        $activedata{ACTIVE_LENGTH}    = $parts[0]*3600+$parts[1]*60+$parts[2];
    }

    my $nexttrack = $main::ZONES{$zone}->{AV}->{"r:NextTrackMetaData"};
    if ($nexttrack) {
        $activedata{NEXT_NAME}      = enc($nexttrack->{item}->{"dc:title"});
        $activedata{NEXT_ARTIST}    = enc($nexttrack->{item}->{"dc:creator"});
        $activedata{NEXT_ALBUM}     = enc($nexttrack->{item}->{"upnp:album"});
        $activedata{NEXT_ISSONG}    = 1;
    }

    $activedata{ZONE_MODE}          = $activedata{ACTIVE_MODE};
    $activedata{ZONE_MUTED}         = $activedata{ACTIVE_MUTED};
    $activedata{ZONE_ID}            = $activedata{ACTIVE_ZONEID};
    $activedata{ZONE_NAME}          = $activedata{ACTIVE_ZONE};
    $activedata{ZONE_VOLUME}        = $activedata{ACTIVE_VOLUME};
    $activedata{ZONE_ARG}           = "zone=".uri_escape($zone)."&";

    my $icon = $main::ZONES{$zone}->{Icon};
    $icon =~ s/^x-rincon-roomicon://;
    $activedata{ZONE_ICON}          = $icon;
    
    $activedata{ZONE_LASTUPDATE}    = $lastupdate;
    my $num_linked                  = $#{$main::ZONES{$zone}->{Members}};
    $activedata{ZONE_NUMLINKED}     = $num_linked;
    $activedata{ZONE_FANCYNAME}     = $activedata{ZONE_NAME};
    $activedata{ZONE_FANCYNAME}     .= " + " . $num_linked if $num_linked;

    my @members;
    foreach (@{$main::ZONES{$zone}->{Members}}) { 
        my %memberdata;
        $memberdata{"ZONE_NAME"}   = $main::ZONES{$_}->{ZoneName};
        $memberdata{"ZONE_ID"}     = $_;
        $memberdata{"ZONE_LINKED"} = int($main::ZONES{$_}->{Coordinator} ne $_);
        $memberdata{"ZONE_ICON"}   = $main::ZONES{$_}->{Icon};
        $memberdata{"ZONE_ICON"}   =~ s/^x-rincon-roomicon://;
        push @members, \%memberdata;
    }
    $activedata{ZONE_MEMBERS}     = \@members;


    if ($main::ZONES{$zone}->{Coordinator} eq $zone) {
        $activedata{ZONE_LINKED}    = 0;
        $activedata{ZONE_LINK}      = "";
        $activedata{ZONE_LINK_NAME} = "";
    } else {
        $activedata{ZONE_LINKED}    = 1;
        $activedata{ZONE_LINK}      = $main::ZONES{$zone}->{Coordinator};
        $activedata{ZONE_LINK_NAME} = enc($main::ZONES{$main::ZONES{$zone}->{Coordinator}}->{ZoneName});
    }

    $activedata{ACTIVE_JSON} = to_json(\%activedata, { pretty => 1});

    return \%activedata;
}

###############################################################################
sub http_build_queue_data {
my ($zone, $updatenum) = @_;

    my %queuedata;

    $queuedata{QUEUE_ZONE}       = enc($main::ZONES{$zone}->{ZoneName});
    $queuedata{QUEUE_ZONEID}     = uri_escape($zone);
    $queuedata{QUEUE_LASTUPDATE} = $main::QUEUEUPDATE{$zone};
    $queuedata{QUEUE_UPDATED}    = ($main::QUEUEUPDATE{$zone} > $updatenum);

    my $i = 1;
    my @loop_data = ();
    my $q = $main::ZONES{$zone}->{QUEUE};
    $q = () unless $q;

    foreach my $queue (@$q) {
        my %row_data;
        my $av = $main::ZONES{$zone}->{AV};
        my $playing = ($av->{TransportState} eq "PLAYING");

        $row_data{QUEUE_NAME}     = enc($queue->{"dc:title"});
        $row_data{QUEUE_ALBUM}    = enc($queue->{"upnp:album"});
        $row_data{QUEUE_ARTIST}   = enc($queue->{"dc:creator"});
        $row_data{QUEUE_TRACK_NUM}= enc($queue->{"upnp:originalTrackNumber"});
        $row_data{QUEUE_ALBUMART} = enc($queue->{"upnp:albumArtURI"});
        $row_data{QUEUE_ARG}      = "zone=" . uri_escape($zone). "&queue=$queue->{id}";
        $row_data{QUEUE_ID}       = $queue->{id};
        push(@loop_data, \%row_data);
        $i++;
    };

    $queuedata{QUEUE_LOOP} = \@loop_data;
    $queuedata{QUEUE_JSON} = to_json(\@loop_data, { pretty => 1});

    return \%queuedata;
}

sub http_build_music_data {
    my $qf = shift;
    my $updatenum = shift;
    my %musicdata;

    my @music_loop_data = ();
    my @page_loop_data = ();
    my $firstsearch = ($qf->{firstsearch}?$qf->{firstsearch}:0);
    my $maxsearch = $main::MAX_SEARCH;
    $maxsearch   = $qf->{maxsearch} if ($qf->{maxsearch});

    my $albumart = "";

    my $mpath = "";
    $mpath = $qf->{mpath} if (defined $qf->{mpath});
    $mpath = "" if ($mpath eq "/");
    my $msearch = $qf->{msearch}; 
    my $item = sonos_music_entry($mpath);
    my $name = enc($item->{'dc:title'});

    $musicdata{"MUSIC_ROOT"} = int($mpath eq "");
    $musicdata{"MUSIC_LASTUPDATE"} = $main::MUSICUPDATE;
    $musicdata{"MUSIC_PATH"} = uri_escape($mpath);
    $musicdata{"MUSIC_NAME"} = enc($item->{'dc:title'});
    $musicdata{"MUSIC_ARTIST"} = enc($item->{'dc:creator'});
    $musicdata{"MUSIC_ALBUM"} = enc($item->{'upnp:album'});
    $musicdata{"MUSIC_UPDATED"} = ($mpath ne "" || (!$qf->{NoWait} && ($main::MUSICUPDATE > $updatenum)));
    $musicdata{"MUSIC_PARENT"} = uri_escape($item->{parentID}) if (defined $item && defined $item->{parentID});
    $musicdata{MUSIC_ARG} = "mpath=" . $musicdata{MUSIC_PATH};

    my $class = $item->{'upnp:class'};
    $musicdata{"MUSIC_CLASS"} = enc($class);

    $musicdata{MUSIC_ISSONG} =  int($class =~ /musicTrack$/);
    $musicdata{MUSIC_ISRADIO} = int($class =~ /audioBroadcast$/);
    $musicdata{MUSIC_ISALBUM} = int($class =~ /musicAlbum$/);

    my $elements = sonos_containers_get($mpath, $item);
    my $need_redirect = sonos_music_isfav($mpath);


    $musicdata{MUSIC_ISPAGED} = int(scalar @{$elements} > $maxsearch);
    my $from = "";
    my $to = "";
    my $count = 0;
    foreach my $music (@{$elements}) {
        my $name = $music->{"dc:title"};
        my $letter = uc(substr($name, 0, 1)); 
        $from = $letter unless $from; 
        $count++;

        if (($count > $maxsearch) && ($letter ne $to)) {
            my %data;
            $data{PAGE_NAME} = "$from-$to" unless ($from eq $to);
            $data{PAGE_NAME} = "$from" if ($from eq $to);
            $data{PAGE_ARG} = "msearch=^[$from-$to]";
            push @page_loop_data, \%data;
            $count = 0;
            $from = $letter;
        }

        $to = $letter;
    }

    # last
    my %data;
    $data{PAGE_NAME} = "$from-$to" unless ($from eq $to);
    $data{PAGE_NAME} = "$from" if ($from eq $to);
    $data{PAGE_ARG} = "msearch=^[$from-$to]";
    push @page_loop_data, \%data;
    $musicdata{"PAGE_LOOP"} = \@page_loop_data;

    foreach my $music (@{$elements}) {
        my %row_data;

        my $row_item = $need_redirect ?
        sonos_music_entry(sonos_music_realpath($music->{id})):
        $music;
        my $class = $row_item->{"upnp:class"}; 
        my $name = $music->{"dc:title"};
        next if ($qf->{'msearch'} && $name !~ m/$qf->{'msearch'}/i);

        $row_data{MUSIC_NAME} = enc($name);
        $row_data{MUSIC_CLASS} = enc($music->{"upnp:class"});
        $row_data{MUSIC_PATH} = enc($music->{id});
        $row_data{MUSIC_REALCLASS} = enc($class);
        $row_data{MUSIC_REALPATH} = enc($row_item->{id});
        $row_data{MUSIC_ARG} = "mpath=" . $row_data{MUSIC_REALPATH};
        $row_data{"MUSIC_ALBUMART"} = sonos_music_albumart($music);
        $musicdata{"MUSIC_ALBUMART"} = $row_data{"MUSIC_ALBUMART"} unless $musicdata{"MUSIC_ALBUMART"};
        $row_data{"MUSIC_ALBUM"} = enc($music->{"upnp:album"});
        $row_data{"MUSIC_ARTIST"} = enc($music->{"dc:creator"});
        $row_data{"MUSIC_DESC"} = enc($music->{"r:description"});
        $row_data{MUSIC_TRACK_NUM}= enc($music->{"upnp:originalTrackNumber"});

        $row_data{MUSIC_ISSONG} =  int($class =~ /musicTrack$/);
        $row_data{MUSIC_ISRADIO} = int($class =~ /audioBroadcast$/);
        $row_data{MUSIC_ISALBUM} = int($class =~ /musicAlbum$/);

        push(@music_loop_data, \%row_data);
        last if ($#music_loop_data > $firstsearch + $maxsearch);
    }

    splice(@music_loop_data, 0, $firstsearch) if ($firstsearch > 0);
    if ($#music_loop_data > $maxsearch) {
        $musicdata{"MUSIC_ERROR"} = "More then $maxsearch matching items.<BR>";
    }

    $musicdata{"MUSIC_LOOP"} = \@music_loop_data;
    
    return \%musicdata;
}
###############################################################################
# Sort items by coordinators first, for linked zones sort under their coordinator
sub http_zone_sort_linked () {
    my $c = $main::ZONES{$main::ZONES{$main::a}->{Coordinator}}->{ZoneName} cmp 
            $main::ZONES{$main::ZONES{$main::b}->{Coordinator}}->{ZoneName};
    return $c if ($c != 0);
    return -1 if ($main::ZONES{$main::a}->{Coordinator} eq $main::a);
    return 1 if ($main::ZONES{$main::b}->{Coordinator} eq $main::b);
    return $main::ZONES{$main::a}->{ZoneName} cmp $main::ZONES{$main::b}->{ZoneName};
}
###############################################################################
# Sort items by coordinators first, for linked zones sort under their coordinator
sub http_zone_sort () {
    return $main::ZONES{$main::a}->{ZoneName} cmp $main::ZONES{$main::b}->{ZoneName};
}

###############################################################################
sub http_zones {
my ($linked) = @_;

    my @zkeys = grep (!exists $main::ZONES{$_}->{Invisible}, keys %main::ZONES);

    if (defined $linked && $linked) {
        return (sort http_zone_sort_linked (@zkeys));
    } else {
        return (sort http_zone_sort (@zkeys));
    }
}

###############################################################################
sub http_build_map {
my ($qf, $params) = @_;

    my $updatenum = 0;
    $updatenum = $qf->{lastupdate} if ($qf->{lastupdate});

    my %map = ();
 
    # globals
    {
        my $globals = {};
        my $host = UPnP::Common::getLocalIP().":".$main::HTTP_PORT; 
        $globals->{"BASE_URL"} = "http://$host";
        $globals->{"VERSION"    } = $main::VERSION;
        $globals->{"LAST_UPDATE"} = $main::LASTUPDATE;
        $globals->{"LAST_UPDATE_READABLE"} = localtime $main::LASTUPDATE;

        my @keys = grep !/action|rand|mpath|msearch|link/, (keys %$qf);
        my $all_arg = "";
        $all_arg .= "$_=$qf->{$_}&" for @keys;
        $globals->{"ALL_ARG"} = $all_arg;

        $globals->{"MUSICDIR_AVAILABLE"} = !($main::MUSICDIR eq "");
        $globals->{"ZONES_LASTUPDATE"} = $main::ZONESUPDATE;
        $globals->{"ZONES_UPDATED"} = ($main::ZONESUPDATE > $updatenum);
        
        $map{GLOBALS_JSON} = to_json($globals, { pretty => 1}, { pretty => 1});
        %map = (%map, %$globals);
    }

    if (grep /^ZONES_/i, @$params) {
        my @zones = map { http_build_zone_data($_, $updatenum, $qf->{zone}); } main::http_zones(1);
        $map{ZONES_LOOP} = \@zones;
        $map{ZONES_JSON} = to_json(\@zones, { pretty => 1});
    }

    if (grep /^ALL_QUEUE_/i, @$params) {
        my @queues = map { http_build_queue_data($_, $updatenum); } main::http_zones(1);
        $map{ALL_QUEUE_LOOP} = \@queues;
        $map{ALL_QUEUE_JSON} = to_json(\@queues, { pretty => 1});
    }

    if (exists $qf->{zone}) {
        my $queue = http_build_queue_data($qf->{zone}, $updatenum);
        $map{QUEUE_JSON} = to_json($queue, { pretty => 1});
        %map = (%map, %$queue);
    }

    if (grep /^MUSIC_/i, @$params) {
        my $music = http_build_music_data($qf, $updatenum);
        $map{MUSIC_JSON} = to_json($music, { pretty => 1});
        %map = (%map, %$music);
    }

    if (exists $qf->{zone}) {
        my $zone = http_build_zone_data($qf->{zone}, $updatenum, $qf->{zone});
        %map = (%map, %$zone);
    }

    if (grep /^PLUGIN_/i, @$params) {
        my @loop_data = ();

        foreach my $plugin (sort (keys %main::PLUGINS)) {
            next if (! $main::PLUGINS{$plugin}->{link});
            my %row_data;
            $row_data{PLUGIN_LINK} = $main::PLUGINS{$plugin}->{link};
            $row_data{PLUGIN_NAME} = $main::PLUGINS{$plugin}->{name};
            
            push(@loop_data, \%row_data);
        }

        $map{"PLUGIN_LOOP"} = \@loop_data;
        $map{"PLUGIN_JZON"} = to_json(\@loop_data, { pretty => 1});
    }


    # Log(4, "\nParams = " . Dumper($params));
    # Log(4, "\nData = " . Dumper(\%map) . "\n");


    return \%map;

}

###############################################################################
sub http_send_tmpl_response {
my ($what, $zone, $c, $r, $diskpath, $tmplhook) = @_;


    my %qf = $r->uri->query_form;
    delete $qf{zone} if (exists $qf{zone} && !exists $main::ZONES{$qf{zone}});

    # One of ours templates, now fill in the parts we know
    my $template = HTML::Template->new(filename => $diskpath,
                                       die_on_bad_params => 0,
                                       global_vars => 1,
                                       use_query => 1,
                                       loop_context_vars => 1);
    my @params = $template->param();
    my $map = http_build_map(\%qf, \@params);
    $template->param(%$map);

    &$tmplhook($c, $r, $diskpath, $template) if ($tmplhook);
    
    my $content_type = "text/html; charset=ISO-8859-1";
    if ($r->uri->path =~ /\.xml/) { $content_type = "text/xml; charset=ISO-8859-1"; }
    if ($r->uri->path =~ /\.json/) { $content_type = "application/json"; }

    my $output = $template->output;
    my $gzoutput; 
    my $status = gzip \$output => \$gzoutput;
    my $response = HTTP::Response->new(200, undef, [Connection => "close",
            "Content-Type" => $content_type, "Pragma" => "no-cache", "Content-Encoding" => "gzip",
            "Cache-Control" => "no-store, no-cache, must-revalidate, post-check=0, pre-check=0"],
        $gzoutput);
    $c->send_response($response);
    $c->force_last_request;
    $c->close;
}

###############################################################################
sub http_quit {
    $main::daemon->close();
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
###############################################################################
sub add_read_socket {
    my ($socket, $cb) = @_;

    $main::SOCKETCB{$socket} = $cb;
    $main::select->add($socket);
}
###############################################################################
sub del_read_socket {
    my ($socket) = @_;

    delete $main::SOCKETCB{$socket};
    $main::select->remove($socket);
}
###############################################################################
sub add_timeout {
    my $time = shift @_;
    my $cb = shift @_;

    @main::TIMERS = sort { $a->[0] <=> $b->[0] } @main::TIMERS, [$time, $cb, @_];
}
###############################################################################
sub is_timeout_cb {
    my ($cb) = @_;

    foreach my $item (@main::TIMERS) {
        return 1 if ($item->[1] == $cb);
    }
    return 0;
}
###############################################################################
sub isLog {
    my $level = shift;

    return 0 if ($level > $main::MAX_LOG_LEVEL);

    return 1;
}
###############################################################################
sub Log {
    my $level = shift;
    my $now = strftime "%e/%H%M%S", localtime;
    my @Level = ("crit", "alert", "notice", "info", "debug");

    return if ($level > $main::MAX_LOG_LEVEL);

    my ($package, $filename, $line) = caller(0);
    my ($x, $y, $z, $subroutine)    = caller(1);
    $subroutine = "*unknown*" if (!defined $subroutine);
    print  "$now $Level[$level]: $filename:$line $subroutine @_\n";
}
###############################################################################
# Copied from newer URI::Escape module
sub uri_escape_utf8
{
    my $text = shift;
    if ($] < 5.008) {
        $text =~ s/([^\0-\x7F])/do {my $o = ord($1); sprintf("%c%c", 0xc0 | ($o >> 6), 0x80 | ($o & 0x3f)) }/ge;
    }
    else {
        utf8::encode($text);
    }

    return uri_escape($text, @_);
}
###############################################################################
@main::DOWNLOADS = ();
$main::DOWNLOADS_PID = undef;

sub download 
{
    my ($url, $file) = @_;

    if (defined $url && defined $file) {
        Log(2, "invoked ($url, $file)");
        push @main::DOWNLOADS, [$url, $file];
    } else {
        Log(4, "invoked from timer");
    }

    # No more download, rebuild music
    if ($#main::DOWNLOADS == -1) {
        sonos_reindex();
        return;
    }

    # Has to be at least one download, keep checking to see when we are done
    if (!is_timeout_cb(\&download)) {
        add_timeout (time()+5, \&download);
    }

    # Already forked so just return
    return if (defined $main::DOWNLOADS_PID && defined $main::CHLD{$main::DOWNLOADS_PID});

    if ($main::DOWNLOADS_PID = fork) {
        # Parent
        Log (4, "Parent");
        $main::CHLD{$main::DOWNLOADS_PID} = 1;
        @main::DOWNLOADS = ();
    } else {
        # Child
        Log (4, "Child");
        my $ua = LWP::UserAgent->new(timeout => 10);
        foreach my $item (@main::DOWNLOADS) {
            Log (4, "fetching @{$item}[0] to @{$item}[1]");
            my $response = $ua->get(@{$item}[0], ":content_file" => @{$item}[1]);
        }
        exit;
    }
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
