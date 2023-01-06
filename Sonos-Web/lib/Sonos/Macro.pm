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