use 5.036000;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Sonos',
    VERSION_FROM      => 'lib/Sonos.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ABSTRACT_FROM     => 'lib/Sonos.pm', # retrieve abstract from module
    AUTHOR            => 'Tom Vander Aa <tom.vanderaa@gmail.com>',
    LICENSE           => 'mit',
);
