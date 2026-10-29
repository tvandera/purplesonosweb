package Sonos::CachePath;

use v5.36;
use strict;
use warnings;

use Exporter qw(import);
use File::Path qw(make_path);
use File::Spec;

our @EXPORT_OK = qw(cache_dir cache_file);

sub cache_dir() {
    my $base = $ENV{XDG_CACHE_HOME};
    if ( !defined($base) || !length($base) || !File::Spec->file_name_is_absolute($base) ) {
        my $home = $ENV{HOME} // die "HOME is not set; cannot determine the XDG cache directory\n";
        $base = File::Spec->catdir( $home, '.cache' );
    }

    my $dir = File::Spec->catdir( $base, 'purplesonosweb' );
    make_path( $dir, { mode => 0700 } ) unless -d $dir;
    return $dir;
}

sub cache_file($basename) {
    return File::Spec->catfile( cache_dir(), $basename );
}

1;