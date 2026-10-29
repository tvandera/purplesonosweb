use v5.36;
use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Temp qw( tempdir );

use Sonos::AlbumArtCache;
use Sonos::CachePath qw( cache_dir cache_file );
use Sonos::LocationCache;
use Sonos::MusicLibrary;

my $home = tempdir( CLEANUP => 1 );
my $xdg_cache_home = File::Spec->catdir( $home, 'xdg-cache' );
local $ENV{HOME} = $home;
local $ENV{XDG_CACHE_HOME} = $xdg_cache_home;

my $app_cache_dir = File::Spec->catdir( $xdg_cache_home, 'purplesonosweb' );
is( cache_dir(), $app_cache_dir, 'uses app-specific XDG cache directory' );
ok( -d $app_cache_dir, 'creates the app cache directory' );
is(
    Sonos::LocationCache->cacheFilename(),
    File::Spec->catfile( $app_cache_dir, 'location_cache.json' ),
    'location cache uses XDG directory',
);
is(
    Sonos::MusicLibrary->cacheFileName(),
    File::Spec->catfile( $app_cache_dir, 'content_cache.json' ),
    'music library cache uses XDG directory',
);
is(
    Sonos::AlbumArtCache->cacheFilename(),
    File::Spec->catfile( $app_cache_dir, 'albumart_cache.json' ),
    'album art index uses XDG directory',
);
is(
    Sonos::AlbumArtCache->cacheDir(),
    File::Spec->catdir( $app_cache_dir, 'albumart_cache' ),
    'album art blobs use a subdirectory of the XDG cache',
);

{
    local $ENV{XDG_CACHE_HOME};
    is(
        cache_dir(),
        File::Spec->catdir( $home, '.cache', 'purplesonosweb' ),
        'falls back to ~/.cache when XDG_CACHE_HOME is unset',
    );
}

done_testing();