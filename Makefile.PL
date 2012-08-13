require 'mk/MY.pm';
require 'mk/MY/Makefile.pm';

my $makefile = MY::Makefile->new(
    'srcdir'        => 'src',
    'scan_manifest' => 1
);

$makefile->write(
    'NAME'         => 'Archive::Tar::Builder',
    'VERSION_FROM' => 'lib/Archive/Tar/Builder.pm',
    'AUTHOR'       => 'Erin Schoenhals <erin@cpanel.net>',
    'LICENSE'      => 'perl',
    'ABSTRACT'     => 'Provides a braindead tarball builder thingie',
    'PMLIBDIRS'    => ['lib'],

    'PREREQ_PM' => {
        'File::Find'   => 0,
        'File::Spec'   => 0,
        'Digest::SHA1' => 0,
        'Math::BigInt' => 0
    },

    'BUILD_REQUIRES' => {
        'Test::Simple'     => '0.44'
    }
);
