use v5.36;
use strict;
use warnings;

require JSON;
use Data::Dumper;
use Template;
use File::Slurp;

my @files = glob('
    html/*.html
    html/*/*.html
    html/*.json
    html/*/*.json
    html/*.js
    html/*/*.js
    html/*.xml
    html/*/*.xml');

my $decoder = JSON->new()->utf8();
my $fname = shift @ARGV;
my $input = read_file($fname);
my $json = $decoder->decode($input);
# print Dumper($json);

for my $fname (@files) {
   print("=======  $fname =======\n");
   my $tt = Template->new({
        STRICT => 1,
        # DEBUG => DEBUG_ALL,
   });

   my $output = '';
   my $ok = $tt->process($fname, $json, \$output);

   print $tt->error(), "\n" unless $ok;
   # print Dumper($output);

   # print Dumper($template);
   # print $template->output();
   # %param_map = (%param_map, $template->{param_map});
}