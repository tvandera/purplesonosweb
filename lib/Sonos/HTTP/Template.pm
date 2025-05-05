package Sonos::HTTP::Template;

use base 'Sonos::HTTP::Builder';

use v5.36;
use strict;
use warnings;



use HTML::Entities;
use URI::Escape;
use Encode qw(encode decode);
use URI::WithBase;
use File::Spec::Functions 'catfile';
require JSON;
use IO::Compress::Gzip qw(gzip $GzipError) ;
use MIME::Types;

require Template;

###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $system, $diskpath, $qf, %args) = @_;
	my $class = ref($self) || $self;

    $self   = $class->SUPER::new($system, $qf, %args);
    my $tt  = $self->{_template} = Template->new();
    my $map = $self->build_all_data();

    my $output = '';
    $tt->process($diskpath, $map, \$output) || die $tt->error(), "\n";

    $self->{_output} = $output;
    return $self;
}

sub template($self) {
    return $self->{_template};
}

sub output($self) {
    return $self->{_output};
}