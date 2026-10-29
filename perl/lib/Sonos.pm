package Sonos;

use 5.036000;
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Sonos::Web ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = (
    'all' => [
        qw(

        )
    ]
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(

);

our $VERSION = '0.90';

# Preloaded methods go here.

1;
__END__

=head1 NAME

Sonos Daemon - Web UI, REST API and CLI for your Sonos System

=head1 SYNOPSIS

  sonod --ip localhost --port 9999 <player1> <player2> ....

  Point your web browser to "http://localhost:9999/" to select interface and plugins

=head1 DESCRIPTION

Purple Sonos is a very simple controller
for the Sonos (http://www.sonos.com) Music System,
although it might work with any UPnP Music System.

Currently it supports:
* All Control functions: Play, Pause, Next, Previous
* All Volume functions: Mute, Louder, Softer
* Adding/Removing items to the queue
* Creating, Deleting, Using saved Playlists
* Selecting Radio Station
* Simple plugins

All the web pages are in the the html directory, and can
be edited freely.  A very simple template system is used
to build everything.

=head1 AUTHOR

Tom Vander Aa, E<lt>tom.vanderaa@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 by Tom Vander Aa

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.36.0 or,
at your option, any later version of Perl 5 you may have available.

Copyright (C) 2006 by Andy Wick

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
