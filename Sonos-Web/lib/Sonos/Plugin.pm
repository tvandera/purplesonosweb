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
