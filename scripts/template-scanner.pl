use v5.36;
use strict;
use warnings;

require JSON;
use Data::Dumper;
use Template;
use File::Slurp;
use File::Basename;


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

for my $fname (@files) {
   print("=======  $fname =======\n");

   my $output = '';
    my $tt = Template->new({
        STRICT => 1,
        INCLUDE_PATH => [ '.', dirname($fname) ],
        RELATIVE => 1,
    });
   my $ok = $tt->process($fname, $json, \$output);

   if ($ok) {
        print("$fname: ✅\n\n");
   } else {
        print $tt->error(), "\n" unless $ok;
   }
}