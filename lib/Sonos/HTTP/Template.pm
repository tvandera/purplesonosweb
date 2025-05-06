package Sonos::HTTP::Template;

use base 'Sonos::HTTP::NestedBuilder';

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

    $self->{_diskpath} = $diskpath;

    my $tt = $self->{_template} = Template->new({
        STRICT => 1,
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