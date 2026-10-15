use v5.36;
use strict;
use warnings;

use Test::More;
use File::Temp qw( tempdir );
use Cwd qw( getcwd );
use Log::Log4perl qw(:easy);
use JSON::XS qw( decode_json );
use File::Slurp qw( read_file );

use Sonos::System;
Log::Log4perl->easy_init($OFF);

my $original_dir = getcwd();
my $cache_dir = tempdir( CLEANUP => 1 );
chdir $cache_dir or die "Cannot enter $cache_dir: $!";
END { chdir $original_dir if defined $original_dir }

my @preloaded;
my $searches = 0;
my $device = {
    UDN => 'uuid:test-player',
    FRIENDLYNAME => 'Test player',
    LOCATION => 'http://player.test:1400/xml/device_description.xml',
};

{
    no warnings 'redefine';
    local *UPnP::ControlPoint::new = sub { bless {}, 'UPnP::ControlPoint' };
    local *UPnP::ControlPoint::searchByType = sub { $searches++ };
    local *UPnP::ControlPoint::addByLocation = sub {
        my ( $controlpoint, $location ) = @_;
        push @preloaded, $location;
        return $location eq $device->{LOCATION} ? $device : undef;
    };
    local *Sonos::Player::new = sub { bless {}, 'Sonos::Player' };
    local *Sonos::MusicLibrary::new = sub { bless {}, 'Sonos::MusicLibrary' };
    local *Sonos::AlbumArtCache::new = sub { bless {}, 'Sonos::AlbumArtCache' };

    my $system = Sonos::System->discover();
    is_deeply( \@preloaded, [], 'First startup has no cached locations' );
    is( $searches, 1, 'First startup searches for players' );

    $system->_discoveryCallback( undef, $device, 'deviceAdded' );
    is_deeply(
        decode_json( read_file('location_cache.json') ),
        { 'test-player' => $device->{LOCATION} },
        'Discovery persists the player location',
    );

    my $restarted = Sonos::System->discover();
    is_deeply( \@preloaded, [ $device->{LOCATION} ], 'Restart preloads cached locations' );
    is( $restarted->numPlayers(), 1, 'Cached player is registered' );
    is( $searches, 2, 'Restart still searches for players' );

    $device->{LOCATION} = 'http://replacement.test:1400/xml/device_description.xml';
    $restarted->_discoveryCallback( undef, $device, 'deviceAdded' );
    is_deeply(
        [ Sonos::LocationCache->new()->locations() ],
        [ $device->{LOCATION} ],
        'Rediscovery replaces the cached address for the same player',
    );

    $restarted->_discoveryCallback( undef, $device, 'deviceRemoved' );
    is_deeply(
        [ Sonos::LocationCache->new()->locations() ],
        [ $device->{LOCATION} ],
        'Temporary removal preserves the cached location',
    );

    $device->{LOCATION} = 'http://offline.test:1400/xml/device_description.xml';
    @preloaded = ();
    my $offline = Sonos::System->discover();
    is( $offline->numPlayers(), 0, 'Unavailable cached player is not registered' );
    is( $searches, 3, 'Unavailable cached player does not prevent discovery' );
    is_deeply(
        [ Sonos::LocationCache->new()->locations() ], [],
        'Failed preload is removed from the persistent cache',
    );

    $offline->locationCache()->add( 'test-player', $device->{LOCATION} );
    $offline->locationCache()->add( 'other-player', 'http://other.test/device.xml' );
    {
        local *UPnP::ControlPoint::addByLocation = sub {
            my ( $controlpoint, $location ) = @_;
            return { %$device, UDN => 'uuid:other-player', LOCATION => $location }
              if $location eq 'http://other.test/device.xml';
            warn "Loading device description failed with error: 500 Can't connect\n";
            next;
        };
        my @warnings;
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        my $failed = Sonos::System->discover();
        is( $failed->numPlayers(), 1, 'Failed preload does not skip healthy players' );
        like( join( '', @warnings ), qr/Loading device description failed/,
            'Connection failure is still reported' );
    }
    is_deeply(
        [ Sonos::LocationCache->new()->locations() ],
        ['http://other.test/device.xml'],
        'UPnP next-on-failure evicts only the failed location',
    );
}

done_testing();