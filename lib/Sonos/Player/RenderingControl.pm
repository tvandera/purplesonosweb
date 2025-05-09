package Sonos::Player::RenderingControl;

use base 'Sonos::Player::Service';

use v5.36;
use strict;
use warnings;

require Types::Serialiser;

sub info($self) {
    $self->log($self->shortName, ":");
    for my $channel ('Master', 'LF', 'RF') {
      my $muted = "";
      $muted = " (muted)" if $self->prop("Mute/$channel");
      $self->log("  $channel volume: " . $self->prop("Volume/$channel") . $muted);
    }
}

sub TO_JSON($self) {
    return {
        "last_update" => $self->lastUpdate(),
        "volume"      => $self->getVolume(),
        "muted"       => Types::Serialiser::as_bool($self->getMute()),
    }
}

sub processUpdate {
    my $self = shift;
    $self->processUpdateLastChange(@_);
    $self->SUPER::processUpdate(@_)
}

sub getVolume($self, $channel = "Master") {
    return $self->prop("Volume/$channel", "int");
}

sub getMute($self, $channel = "Master") {
    return $self->prop("Mute/$channel", "int");
}

sub setVolume($self, $value, $channel = "Master") {
    $value = 0 if $value < 0;
    $value = 100 if $value > 100;

    return 0 if $value == $self->getVolume($channel);
    return $self->action("SetVolume", $channel, $value);
}

sub changeVolume($self, $diff, $channel = "Master") {
    my $vol = $self->getVolume($channel) + $diff;
    $self->setVolume($vol, $channel);
}

sub MuchSofter($self) { $self->changeVolume(-5); }
sub Softer    ($self) { $self->changeVolume(-1); }
sub Louder    ($self) { $self->changeVolume(+1); }
sub MuchLouder($self) { $self->changeVolume(+5); }

# muting
sub setMute($self, $on_or_off, $channel = "Master") {
    return 0 if $on_or_off == $self->getMute($channel);
    return $self->action("SetMute", $channel, $on_or_off)
}

sub muteOn ($self) { $self->setMute(1); }
sub muteOff($self) { $self->setMute(0); }

1;