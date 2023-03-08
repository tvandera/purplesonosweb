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

require HTML::Template;

###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $system, $diskpath, $qf, %args) = @_;
	my $class = ref($self) || $self;

    $self = $class->SUPER::new($system, $qf, %args);

    # One of our templates, now fill in the parts we know
    my $template = $self->{_template} = HTML::Template->new(
        filename          => $diskpath,
        die_on_bad_params => 0,
        global_vars       => 1,
        use_query         => 1,
        loop_context_vars => 1
    );

    my $map    = $self->build_all_data();
    $template->param(%$map);

    return $self;
}

sub template($self) {
    return $self->{_template};
}

sub output($self) {
    return $self->template()->output();
}