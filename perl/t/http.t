use strict;
use warnings;

use File::Temp qw(tempfile);
use Test::More tests => 3;
use Sonos::HTTP::Template;

BEGIN { use_ok('Sonos::HTTP') };

can_ok('Sonos::HTTP', qw(registerHandler validateRequest validateAction));

{
	my ( $handle, $diskpath ) = tempfile( SUFFIX => '.html', TMPDIR => 1, UNLINK => 1 );
	print {$handle} '<h1>[% title %]</h1>';
	close $handle or die "Could not close template: $!";

	no warnings 'redefine';
	local *Sonos::HTTP::Template::input = sub { return { title => 'Sonos' } };

	my $template = Sonos::HTTP::Template->new( undef, $diskpath, {} );
	is( eval { $template->output() }, '<h1>Sonos</h1>', 'renders a template using an absolute disk path' );
	diag $@ if $@;
}
