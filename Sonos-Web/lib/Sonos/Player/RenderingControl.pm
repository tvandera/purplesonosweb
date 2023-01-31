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

# handled in base class
sub processUpdate {
    my $self = shift;
    $self->processStateUpdate(@_);
}

1;