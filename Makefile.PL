use 5.036000;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Sonos',
    VERSION_FROM      => 'lib/Sonos.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
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
        'UPnP::ControlPoint'         => '0.4',
        'URI::Escape'                => 0,
        'XML::LibXML::Simple'        => 0,
        'XML::Liberal'               => 0,
        'XML::Simple'                => 0,
    },
    ABSTRACT_FROM     => 'lib/Sonos.pm', # retrieve abstract from module
    AUTHOR            => 'Tom Vander Aa <tom.vanderaa@gmail.com>',
    LICENSE           => 'mit',
);
