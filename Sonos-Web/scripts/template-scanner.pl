use v5.36;
use strict;
use warnings;

use Data::Dumper;

require Sonos::System;
require HTML::Template;

require IO::Async::Loop;


my @locations = (
    'http://192.168.2.100:1400/xml/device_description.xml',
    'http://192.168.2.198:1400/xml/device_description.xml',
);

#my $loop = IO::Async::Loop->new;
#my $system = Sonos::System->discover($loop, @locations);
#$system->wait();
#my @players = $system->players();
#my $player = shift @players;

my @files = glob('
    html/*.html 
    html/*/*.html 
    html/*.json 
    html/*/*.json 
    html/*.js
    html/*/*.js
    html/*.xml
    html/*/*.xml');

my @tags = qw(TMPL_IF TMPL_LOOP TMPL_UNLESS TMPL_VAR);

my %param_map = ();

for my $fname (@files) {
    my $template = HTML::Template->new(
        filename          => $fname,
        die_on_bad_params => 0,
        global_vars       => 1,
        use_query         => 1,
        loop_context_vars => 1
   );
   print Dumper($template);
   # %param_map = (%param_map, $template->{param_map});
}