package Sonos::Config;

###############################################################################
# Default config if config.pl doesn't exist

$Config::MAX_LOG_LEVEL  = 0;    # Lower, the less output
$Config::HTTP_PORT      = 8001; # Port our fake http server listens on
$Config::MAX_SEARCH     = 500;  # Default max search results to return
$Config::RENEW_SUB_TIME = 1800; # How often do we do a UPnP renew in seconds
$Config::DEFAULT        = "index.html";
$Config::MUSICDIR       = "";   # Local directory that sonos indexs that we can create music files in
$Config::PASSWORD       = "";   # Password for basic auth
$Config::IGNOREIPS      = "";   # Ignore this ip

sub readconfig {
    do "./config.pl" if (-f "./config.pl");
    foreach my $ip (split (",", $Config::IGNOREIPS)) {
        $UPnP::ControlPoint::IGNOREIP{$ip} = 1;
    }
}

sub doconfig {
    print  "Configure the defaults for sonos.pl by creating a config.pl file.\n";
    print  "Press return or enter key to keep current values.\n";
    print  "Remove the config.pl to reset to the system defaults.\n";
    print  "\n";
    print  "Port to listen on [$Config::HTTP_PORT]: ";
    my $port = int(<STDIN>);
    $port = $Config::HTTP_PORT if ($port == 0);
    $port = 8001 if ($port > 0xffff || $port <= 0);

    print  "Max log level 0=crit 4=debug [$Config::MAX_LOG_LEVEL]: ";
    my $loglevel = int(<STDIN>);
    $loglevel = $Config::MAX_LOG_LEVEL if ($loglevel == 0);
    $loglevel = 1 if ($loglevel < 0 || $loglevel > 4);

    print  "Max search results [$Config::MAX_SEARCH]: ";
    my $maxsearch = int(<STDIN>);
    $maxsearch = $Config::MAX_SEARCH if ($maxsearch == 0);
    $maxsearch = 500 if ($maxsearch < 0);

    print  "Default web page, must exist in html directory [$Config::DEFAULT]: ";
    my $defaultweb = <STDIN>;
    $defaultweb =~ s/[\r\n]//m;
    if ($defaultweb eq " ") {
        $defaultweb = "";
    } elsif ($defaultweb eq "") {
        $defaultweb = $Config::DEFAULT;
    }
    die "The file html/$defaultweb was not found\n" if ($defaultweb ne "" && ! -f "html/$defaultweb");

    print  "\n";
    print  "Location on local disk that Sonos indexes, a subdirectory SonosWeb will be created.\n";
    print  "Use forward slashes only (ex c:/Music), enter single space to clear [$Config::MUSICDIR]: ";
    my $musicdir = <STDIN>;
    $musicdir =~ s/[\r\n]//m;
    if ($musicdir eq " ") {
        $musicdir = "";
    } elsif ($musicdir eq "") {
        $musicdir = "$Config::MUSICDIR";
    }
    die "$musicdir is not a directory\n" if ($musicdir ne "" &&  ! -d $musicdir);

    print  "\n";
    print  "Password for access to web site. (Notice, this isn't secure at all.)\n";
    print  "Enter single space to clear [$Config::PASSWORD]: ";
    my $password = <STDIN>;
    $password =~ s/[\r\n]//m;
    if ($password eq " ") {
        $password = "";
    } elsif ($password eq "") {
        $password = "$Config::PASSWORD";
    }

    print  "\n";
    print  "Ignore traffic from these comma seperated ips\n";
    print  "Enter single space to clear [$Config::IGNOREIPS]: ";
    my $ignoreips = <STDIN>;
    $ignoreips =~ s/[\r\n]//m;
    if ($ignoreips eq " ") {
        $ignoreips = "";
    } elsif ($ignoreips eq "") {
        $ignoreips = "$Config::IGNOREIPS";
    }

    open (CONFIG, ">./config.pl");
    print CONFIG "# This file uses perl syntax\n";
    print CONFIG "\$Config::HTTP_PORT = $port;\n";
    print CONFIG "\$Config::MAX_LOG_LEVEL = $loglevel;\n";
    print CONFIG "\$Config::MAX_SEARCH = $maxsearch;\n";
    print CONFIG "\$Config::DEFAULT = \"$defaultweb\";\n";
    print CONFIG "\$Config::MUSICDIR =\"$musicdir\";\n";
    print CONFIG "\$Config::PASSWORD =\"$password\";\n";
    print CONFIG "\$Config::IGNOREIPS =\"$ignoreips\";\n";
    close CONFIG;
    print  "\nPlease restart sonos.pl now\n";

    exit 0;
}

1;