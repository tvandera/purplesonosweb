package Sonos::Player::RenderingControl;

use base 'Sonos::Player::Service';

use v5.36;
use strict;
use warnings;

use Data::Dumper;
use Carp;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($DEBUG);

sub info($self) {
    $self->log($self->shortName, ":");
    for my $channel ('Master', 'LF', 'RF') {
      my $muted = "";
      $muted = " (muted)" if $self->prop("Mute", $channel);
      $self->log(" $channel: " . $self->prop("Volume", $channel) . $muted);
    }
}

sub getVolume($self, $channel = "Master") {
    return $self->prop("Volume", $channel);
}

sub getMute($self, $channel = "Master") {
    return $self->prop("Mute", $channel);
}

sub setVolume($self, $value) {
    $self->action("SetVolume", "Master", $value);
}

sub changeVolume($self, $diff) {
    my $vol = $self->getVolume() + $diff;
    $self->setVolume($vol);
}

sub setMute($self, $on_or_off) {
    return if $on_or_off == $self->getMute();
    return $self->action("SetMute", "Master", $on_or_off)
}



1;