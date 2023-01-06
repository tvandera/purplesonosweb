###############################################################################
# PLUGINS
###############################################################################

###############################################################################
sub plugin_load {
    Log( 1, "Loading Plugins" );

    eval "us" . "e lib '.'";    # Defeat pp stripping
    opendir( DIR, "Plugins" ) || return;

    for my $plugin ( readdir(DIR) ) {
        if ( $plugin =~ /(.+)\.pm$/ ) {
            $main::PLUGINS{$plugin} = () if ( !$main::PLUGINS{$plugin} );
            $main::PLUGINS{$plugin}->{require} = "Plugins::" . $1;

        }
        elsif ( -d "Plugins/$plugin" && -e "Plugins/$plugin/Plugin.pm" ) {
            $main::PLUGINS{$plugin} = () if ( !$main::PLUGINS{$plugin} );
            $main::PLUGINS{$plugin}->{require} =
              "Plugins::" . $plugin . "::Plugin";
            if ( -d "Plugins/$plugin/html" ) {
                $main::PLUGINS{$plugin}->{html} = "Plugins/$plugin/html/";
            }

        }
    }
    closedir(DIR);

    # First load the plugins
    foreach my $plugin ( keys %main::PLUGINS ) {
        eval "require " . $main::PLUGINS{$plugin}->{require};
        if ($@) {
            Log( 0, "Did not load $plugin: " . $@ );
            delete $main::PLUGINS{$plugin};
            next;
        }
    }

# Now init the plugins.  We do in two steps so plugin inits can talk to other plugins
    foreach my $plugin ( keys %main::PLUGINS ) {
        eval "Plugins::${plugin}::init();";
        if ($@) {
            Log( 0, "Did not init $plugin: " . $@ );
            delete $main::PLUGINS{$plugin};
            next;
        }
    }
}

###############################################################################
sub plugin_register {
    my ( $plugin, $name, $link, $tmplhook ) = @_;

    $main::PLUGINS{$plugin}->{name}     = $name;
    $main::PLUGINS{$plugin}->{link}     = $link;
    $main::PLUGINS{$plugin}->{tmplhook} = $tmplhook;
}

###############################################################################
sub plugin_quit {
    foreach my $plugin ( keys %main::PLUGINS ) {
        eval "Plugins::${plugin}::quit();";
        if ($@) {
            Log( 0, "Can not quit $plugin: " . $@ );
        }
    }
}

###############################################################################
sub sonos_prefsdb_save {
    {
        local $Data::Dumper::Purity = 1;
        Log( 1, "Saving Prefs DB" );
        open( DB, ">prefsdb.pl" );
        my $dumper =
          Data::Dumper->new( [ \%main::PREFS ], [qw( *main::PREFS)] );
        print DB $dumper->Dump();
        close DB;
        Log( 1, "Finshed Saving Prefs DB" );
    }
}
###############################################################################
sub sonos_prefsdb_load {
    if ( -f "prefsdb.pl" ) {
        Log( 1, "Loading Prefs DB" );
        do "./prefsdb.pl";

        if ($@) {
            Log( 0, "Error loading Prefs DB: $@" );
        }
    }
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
