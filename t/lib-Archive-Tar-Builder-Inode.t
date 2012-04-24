#!/usr/bin/perl

# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

use strict;
use warnings;

use Test::Exception;
use Test::More ( 'tests' => 60 );

use Archive::Tar::Builder::Inode ();
use Archive::Tar::Builder::Bits;

my $file    = '/dev/null';
my $badfile = '/dev/null/foo';
my @st      = stat($file) or die("Unable to stat() $file: $!");

my %TESTS = (
    'file'  => $S_IFREG | 0644,
    'dir'   => $S_IFDIR | 0755,
    'link'  => $S_IFLNK | 0777,
    'char'  => $S_IFCHR | 0644,
    'block' => $S_IFBLK | 0644,
    'fifo'  => $S_IFIFO | 0644
);

#
# Branch coverage
#
throws_ok {
    Archive::Tar::Builder::Inode->stat($badfile);
}
qr/^Unable to stat\(\) $badfile:/, 'Archive::Tar::Builder::Inode->stat() dies when unable to stat() file';

my $inode;

lives_ok {
    $inode = Archive::Tar::Builder::Inode->stat($file);
}
'Archive::Tar::Builder::Inode->stat() succeeds when a valid file is passed';

isa_ok( $inode, 'Archive::Tar::Builder::Inode', 'Archive::Tar::Builder::Inode->stat()' );

throws_ok {
    Archive::Tar::Builder::Inode->lstat($badfile);
}
qr/^Unable to lstat\(\) $badfile:/, 'Archive::Tar::Builder->lstat() dies when unable to lstat() file';

lives_ok {
    $inode = Archive::Tar::Builder::Inode->lstat($file);
}
'Archive::Tar::Builder::Inode->lstat() succeeds when a valid file is passed';

isa_ok( $inode, 'Archive::Tar::Builder::Inode', 'Archive::Tar::Builder::Inode->lstat()' );

#
# Functional testing
#
my @tests = sort keys %TESTS;

foreach my $test (@tests) {
    my $mode = $TESTS{$test};

    my @fake_stat = ( 0, 0, $mode );
    my $fake_inode = bless \@fake_stat, 'Archive::Tar::Builder::Inode';

    is( $fake_inode->mode => $mode,            '$inode->mode() returns full mode and format' );
    is( $fake_inode->perm => $mode & $S_IPERM, '$inode->perm() returns only permissions' );
    is( $fake_inode->fmt  => $mode & $S_IFMT,  '$inode->>fmt() returns only inode format' );

    foreach my $subtest (@tests) {
        if ( $subtest eq $test ) {
            my $message = sprintf( "\$inode->%s() returns true for mode 0%o", $subtest, $mode );
            ok( $fake_inode->$subtest(), $message );
        }
        else {
            my $message = sprintf( "\$inode->%s() returns false for mode 0%o", $subtest, $mode );
            ok( !$fake_inode->$subtest(), $message );
        }
    }
}
