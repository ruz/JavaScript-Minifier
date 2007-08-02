use 5.8.0;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'JavaScript::Minifier',
    VERSION_FROM      => 'lib/JavaScript/Minifier.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/JavaScript/Minifier.pm', # retrieve abstract from module
       AUTHOR         => 'Peter Michaux <petermichaux@gmail.com>') : ()),
);
