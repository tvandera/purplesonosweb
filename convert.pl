#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;

# Check input
die "Usage: $0 input_file.tmpl [output_file.tt]" unless @ARGV >= 1;

my $input_file  = $ARGV[0];
my $output_file = $ARGV[1] // do {
    my ($name, $path, $suffix) = fileparse($input_file, qr/\.[^.]*/);
    "$path$name.tt"
};

open my $in,  '<', $input_file  or die "Cannot open $input_file: $!";
open my $out, '>', $output_file or die "Cannot write to $output_file: $!";

while (<$in>) {
    s{<TMPL_VAR\s+NAME="?(.*?)"?\s*/?>}{[% $1 %]}gi;
    s{<TMPL_IF\s+NAME="?(.*?)"?>}{[% IF $1 %]}gi;
    s{<TMPL_UNLESS\s+NAME="?(.*?)"?>}{[% UNLESS $1 %]}gi;
    s{</TMPL_IF>}{[% END %]}gi;
    s{</TMPL_UNLESS>}{[% END %]}gi;
    s{<TMPL_ELSE>}{[% ELSE %]}gi;

    # Convert TMPL_LOOP
    s{<TMPL_LOOP\s+NAME="?(.*?)"?>}{[% FOREACH item IN $1 %]}gi;
    s{</TMPL_LOOP>}{[% END %]}gi;
    s{<TMPL_VAR\s+NAME="?(.*?)"?\s*/?>}{[% item.$1 %]}gi if /FOREACH item IN/;

    # Convert TMPL_INCLUDE
    s{<TMPL_INCLUDE\s+NAME="?(.*?)"?\s*/?>}{[% INCLUDE $1 %]}gi;

    print $out $_;
}

close $in;
close $out;

print "Converted: $input_file → $output_file\n";

