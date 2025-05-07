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
use URI::Escape;
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

    $self->{"_json"}
        ->pretty(1)
        ->canonical(1)
        ->convert_blessed(1)
        ->utf8(1);

    return $self;
}

sub system($self) {
    return $self->{"_system"};
}

sub players($self) {
    return $self->system()->players();
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
    return $item->TO_JSON($player);
}

sub build_none_data($self) {
    return {};
}

sub build_zones_data($self) {
    return [ map { $self->build_zone_data( $_ ) } $self->players() ];
}


sub build_player_data($self, $player = undef) {
    $player = $self->player() unless $player;
    return {} unless $player;
    return $player->TO_JSON();
}

sub build_zone_data {
    build_player_data @_;
}

sub build_queue_data($self) {
    my $player = $self->player();
    return {} unless $player;
    return $player->queue()->TO_JSON();
}

sub build_music_data($self) {
    my $music   = $self->system()->musicLibrary();
    return $music->TO_JSON($self->qf());
}

sub build_system_data($self) {
    return $self->system()->TO_JSON($self->qf());
}

sub encode_arg($self, $key) {
    my $value = uri_escape_utf8($self->qf($_));
    return $value ? "$key=$value&" : "";
}

sub build_url_data($self) {
    my @keys = qw(zone what action rand mpath msearch link queue);
    my %values = map { $_ =>  $self->qf($_) } @keys;
    my %args = map { $_ => $self->encode_arg($_) } @keys;
    $args{"all"} = join "&", map { $self->encode_arg($_) } keys %{$self->qf()};
    return {
        "args" => { %args },
        "values" => { %values },
    };
}

sub build_all_data($self) {
    my $ret = $self->build_system_data();
    $ret->{"url"} = $self->build_url_data();
    return $ret;
}