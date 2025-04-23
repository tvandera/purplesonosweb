package Sonos::HTTP::NestedBuilder;

use v5.36;
use strict;
use warnings;


require IO::Async::Listener;
require HTTP::Daemon;
use HTTP::Status ":constants";
use HTML::Entities;
use URI::Escape;
use Encode qw(encode decode);
use URI::WithBase;
use File::Spec::Functions 'catfile';
require JSON;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use MIME::Types;

###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $system, $qf, %args) = @_;
	my $class = ref($self) || $self;

    $self = bless {
        _system => $system,
        _qf => $qf,
        _json => JSON->new(),
    }, $class;

    $self->{"_json"}->pretty(1)->canonical(1);

    return $self;
}

sub version($self) {
    return "0.99";
}

sub system($self) {
    return $self->{"_system"};
}

sub players($self, $sorted = 1) {
    return $self->system()->players($sorted);
}

sub lastUpdate($self) {
    return $self->system()->lastUpdate();
}

sub player($self, $name_or_uuid = undef) {
    $name_or_uuid = $self->qf("zone") unless $name_or_uuid;
    return $self->system()->player($name_or_uuid) if $name_or_uuid;
    return; # undef
}

sub qf($self, $field = undef, $default = undef) {
    return $self->{"_qf"} unless $field;
    my $value = $self->{"_qf"}->{$field};
    return $value ? $value : $default;
}

sub log($self, @args) {
    $self->system()->log("template", @args);
}

sub to_json {
    my $self = shift;
    $self->{"_json"}->encode(@_);
}


sub build_item_data($self, $item, $player = undef) {
    return $item->toJSON($player);
}

sub build_none_data($self) {
    return {};
}

###############################################################################
sub build_zones_data($self) {
    my @zones = map { $self->build_zone_data( $_ ) } $self->players();
    return { "zones" => \@zones };
}


###############################################################################
sub build_zone_data($self, $player = undef) {
    $player = $self->player() unless $player;
    return {} unless $player;
    return $player->toJSON();
}

sub build_info_data {
    return build_zone_data @_;
}

###############################################################################
sub build_queue_data($self) {
    my $player = $self->player();
    return {} unless $player;
    return $player->queue()->toJSON();
}

sub build_music_data($self) {
    my $music   = $self->system()->musicLibrary();
    my $mpath   = $self->qf("mpath", "");
    my $msearch = $self->qf("msearch");
    return $music->toJSON($mpath, $msearch);
}

sub build_globals_data($self) {
    my $updatenum = $self->qf("updatenum", -1);

    my $globals = {};
    $globals->{"version"}              = $self->version();
    $globals->{"last_update"}          = $self->lastUpdate();
    $globals->{"last_update_readable"} = localtime $self->lastUpdate();

    my $qf = $self->qf();
    my @keys    = grep !/action|rand|mpath|msearch|link/, ( keys %$qf );
    my $all_arg = join "&", map { "$_=$qf->{$_}" } @keys;
    $all_arg .= "&" if $all_arg;
    $globals->{"all_arg"} = $all_arg;

    $globals->{"musicdir_available"} = 0;
    $globals->{"zones_lastupdate"}   = $self->lastUpdate(); # FIXME
    $globals->{"zones_updated"}      = int( $self->lastUpdate() > $updatenum );

    return $globals;
}

###############################################################################
sub build_all_data($self) {
    my @categories = ( "globals", "zone", "queue", "music", "zones" ) ;
    my %methods = map { $_ => "build_" . $_ . "_data" } @categories;
    my %data = ();
    while (my ($key, $value) = each(%methods)) {
        $data{$key} = $self->$value();
    }
    return \%data;
}