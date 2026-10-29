use 5.036000;
use ExtUtils::MakeMaker;
use File::Find qw( find );

my %install_files;
find(
    sub {
        return unless -f $_;

        my $source = $File::Find::name;
        my $relative = $source;
        my $destination;

        if ( $relative =~ s{^lib/}{} ) {
            $destination = '$(INST_LIB)/' . $relative;
        }
        $install_files{$source} = $destination if defined $destination;
    },
    qw( lib ),
);

sub MY::postamble {
    return <<'MAKE_FRAG';
install :: install_html

install_html:
	$(NOECHO) $(MKPATH) $(INSTALLSITELIB)/../html
	$(NOECHO) cp -R html/. $(INSTALLSITELIB)/../html/

MAKE_FRAG
}

WriteMakefile(
    NAME              => 'Sonos',
    VERSION_FROM      => 'lib/Sonos.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
    PM                => \%install_files,
    EXE_FILES         => [ sort glob 'scripts/*' ],
    PREREQ_PM         => {
        'File::MimeInfo::Magic'      => 0,
        'File::Slurp'                => 0,
        'HTML::Entities'             => 0,
        'HTML::Parser'               => 0,
        'HTTP::Daemon'               => 0,
        'HTTP::Status'               => 0,
        'Image::Resize'              => 0,
        'IO::Async'                  => 0,
        'IO::Async::Timer::Periodic' => 0,
        'IO::Compress::Gzip'         => 0,
        'IO::Scalar'                 => 0,
        'JSON'                       => 0,
        'JSON::Path'                 => 0,
        'JSON::XS'                   => 0,
        'List::MoreUtils'            => 0,
        'Log::Log4perl'              => 0,
        'LWP::MediaTypes'             => 0,
        'LWP::UserAgent'             => 0,
        'MIME::Base64'                => 0,
        'MIME::Types'                 => 0,
        'Net::Async::HTTP::Server'   => 0,
        'Scalar::Util::Numeric'      => 0,
        'SOAP::Lite'                 => 0,
        'Template'                   => 0,
        'Text::Table'                => 0,
        'Try::Tiny'                  => 0,
        'Types::Serialiser'          => 0,
        'UPnP::ControlPoint'         => '0.5',
        'URI::Escape'                => 0,
        'XML::LibXML::Simple'        => 0,
        'XML::Liberal'               => 0,
        'XML::Simple'                => 0,
    },
    ABSTRACT_FROM     => 'lib/Sonos.pm', # retrieve abstract from module
    AUTHOR            => 'Tom Vander Aa <tom.vanderaa@gmail.com>',
    LICENSE           => 'mit',
);
