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
my $stash = $decoder->decode($input);

# Flatten the stash to top-level dot notation for easy checking
sub flatten_stash {
     my @loopvars = ( 'item', 'player' );

    my ($data, $prefix) = @_;
    my %flat = map { $_ => 1 } @loopvars;
    $prefix //= '';
    for my $key (keys %$data) {
        my $full = $prefix ? "$prefix.$key" : $key;
        if (ref $data->{$key} eq 'HASH') {
            %flat = (%flat, flatten_stash($data->{$key}, $full));
        } elsif (ref $data->{$key} eq 'ARRAY') {
            $flat{$full} = 1;
            %flat = (%flat, flatten_stash($data->{$key}->[0], $_)) for @loopvars;
        } else {
            $flat{$full} = 1;
        }
    }

    my @vars = sort keys %flat;
    # print "Available variables:\n", join("\n", @vars), "\n\n";

    return %flat;
}


sub scan($template_file) {
     # Read template content
     my $template_text = read_file($template_file);

     # Extract TT variable references
     my @used_vars = $template_text =~ m/
     \[\%\s*             # opening tag
     (?:IF|UNLESS|END|ELSE|ELSEIF|FOREACH|WHILE)?\s*  # optional directive
     ([a-zA-Z_][\w\.]*)  # variable name with optional dots
     (?!\s*=\s*)         # not assignment
     [^\%\]]*            # ignore rest
     \%\]
     /gx;

     # Flatten and check
     my %flat_stash = flatten_stash($stash);
     my %seen;
     @used_vars = grep { !$seen{$_}++ } @used_vars;  # remove duplicates

     # Remove TT keywords
     my %keywords = ( "END" => 1, "ELSE" => 1 );
     @used_vars = grep { !$keywords{$_}++ } @used_vars;  # remove keywords

     print "Checking template: $template_file\n";
     print "Used variables:\n";

     my $missing = 0;
     for my $var (@used_vars) {
          print " - $var";
          if (exists $flat_stash{$var}) {
               # print " ✔️ defined\n";
          } else {
               print " ❌ undefined\n";
               $missing++;
          }
     }

     if ($missing) {
          print "\nFound $missing undefined variable(s).\n";
     } else {
          print "\nAll variables are defined.\n";
     }
}


sub instantiate($fname, $input)
{
    my $output = '';
    my $tt = Template->new({
        STRICT => 0,
        INCLUDE_PATH => [ '.', dirname($fname) ],
        DEBUG => 'undef',
        RELATIVE => 1,
    });

   my $ok = $tt->process($fname, $input, \$output);

   if ($ok) {
        print("$fname: ✅\n");
   } else {
        print $tt->error(), "\n" unless $ok;
   }
}


for my $fname (@ARGV) {
   print("\n=======  $fname =======\n");
   scan($fname);
   instantiate($fname, $stash);
}