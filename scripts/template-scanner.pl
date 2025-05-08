use v5.36;
use strict;
use warnings;

require JSON;
use Data::Dumper;
use Template;
use File::Slurp;
use File::Basename;

my $decoder = JSON->new()->utf8();
my $fname = shift @ARGV;
my $input = read_file($fname);
my $json = $decoder->decode($input);

for my $fname (@ARGV) {
   print("\n=======  $fname =======\n");

   my $output = '';
    my $tt = Template->new({
        STRICT => 0,
        INCLUDE_PATH => [ '.', dirname($fname) ],
        DEBUG => 'undef',
        RELATIVE => 1,
    });
   my $ok = $tt->process($fname, $json, \$output);

   if ($ok) {
        print("$fname: ✅\n");
   } else {
        print $tt->error(), "\n" unless $ok;
   }
}