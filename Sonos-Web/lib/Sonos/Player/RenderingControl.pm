package Sonos::Player::RenderingControl;

use base 'Sonos::Player::Service';

use v5.36;
use strict;
use warnings;



sub info($self) {
    $self->log($self->shortName, ":");
    for my $channel ('Master', 'LF', 'RF') {
      my $muted = "";
      $muted = " (muted)" if $self->prop("Mute", $channel);
      $self->log(" $channel: " . $self->prop("Volume", $channel) . $muted);
    }
}


sub processUpdate {
    my $self = shift;
    $self->processUpdateLastChange(@_);
    $self->SUPER::processUpdate(@_)
}

sub getVolume($self, $channel = "Master") {
    return $self->prop("Volume", $channel);
}

sub getMute($self, $channel = "Master") {
    return $self->prop("Mute", $channel);
}

sub setVolume($self, $value, $channel = "Master") {
    $self->action("SetVolume", $channel, $value);
}

sub changeVolume($self, $diff, $channel = "Master") {
    my $vol = $self->getVolume($channel) + $diff;
    $self->setVolume($vol, $channel);
}

sub setMute($self, $on_or_off, $channel = "Master") {
    return if $on_or_off == $self->getMute($channel);
    return $self->action("SetMute", $channel, $on_or_off)
}



1;