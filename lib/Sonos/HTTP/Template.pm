package Sonos::HTTP::Template;

use base 'Sonos::HTTP::Builder';

use v5.36;
use strict;
use warnings;



use HTML::Entities ();
use URI::Escape ();
use Encode ();
use URI::WithBase ();
use File::Spec::Functions ();
use File::Basename qw( dirname );
use JSON ();
use IO::Compress::Gzip ();
use MIME::Types ();

use Template ();




###############################################################################
# HTTP
###############################################################################

sub new {
    my($self, $system, $diskpath, $qf, %args) = @_;
	my $class = ref($self) || $self;

    $self   = $class->SUPER::new($system, $qf, %args);

    $self->{_diskpath} = $diskpath;

    my $tt = $self->{_template} = Template->new({
        # STRICT => 1,
        RELATIVE => 1,
        INCLUDE_PATH => [ '.', dirname($diskpath) ],
        # DEBUG => DEBUG_ALL,
    });

    return $self;
}

sub template($self) {
    return $self->{_template};
}

sub input($self) {
    return $self->build_all_data();
}
sub output($self) {
    my $tt = $self->template();
    my $output = '';
    $tt->process($self->{_diskpath}, $self->input(), \$output) || die $tt->error(), "\n";
    return $output;
}

1;