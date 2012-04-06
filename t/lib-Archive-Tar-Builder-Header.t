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
use Test::More ( 'tests' => 86 );

use File::Temp ();

use Archive::Tar::Builder::Header ();
use Archive::Tar::Builder::Inode  ();

my %FIELDS = (
    'path'          => [ 's', 0,   100, 'filename (UStar suffix)' ],
    'mode'          => [ 'o', 100, 8,   'mode' ],
    'uid'           => [ 'o', 108, 8,   'uid' ],
    'gid'           => [ 'o', 116, 8,   'gid' ],
    'size'          => [ 'o', 124, 12,  'size' ],
    'mtime'         => [ 'o', 136, 12,  'mtime' ],
    'type'          => [ 's', 156, 1,   'link type' ],
    'dest'          => [ 's', 157, 100, 'symlink destination' ],
    'ustar'         => [ 's', 257, 6,   'UStar magic' ],
    'ustar_version' => [ 's', 263, 2,   'UStar version' ],
    'user'          => [ 's', 265, 32,  'owner username' ],
    'group'         => [ 's', 297, 32,  'owner group name' ],
    'major'         => [ 'o', 329, 8,   'device major number' ],
    'minor'         => [ 'o', 337, 8,   'device minor number' ],
    'prefix'        => [ 's', 345, 155, 'ustar filename prefix' ]
);

sub test_oct {
    my ( $data, $field, $value ) = @_;
    my ( $type, $offset, $len, $desc ) = @{ $FIELDS{$field} };

    my $message = sprintf( "%s header field equals 0%o", $desc, $value );

    return is( oct( substr( $data, $offset, $len ) ) => $value, $message );
}

sub test_str {
    my ( $data, $field, $value ) = @_;
    my ( $type, $offset, $len, $desc ) = @{ $FIELDS{$field} };

    my $message = sprintf( "%s header field contains '%s'", $desc, $value );

    return is( substr( $data, $offset, length($value) ) => $value, $message );
}

sub test_header {
    my ( $data, %expected ) = @_;

    foreach my $test ( sort keys %expected ) {
        if ( $FIELDS{$test}->[0] eq 's' ) {
            test_str( $data, $test, $expected{$test} );
        }
        elsif ( $FIELDS{$test}->[0] eq 'o' ) {
            test_oct( $data, $test, $expected{$test} );
        }
    }
}

my $tmpdir = File::Temp::tempdir(
    '/tmp/.test-XXXXXX',
    'CLEANUP' => 1
);

# Test regular files
{
    note('Testing regular files');

    my $file = "$tmpdir/file";

    open( my $fh, '>', $file ) or die("Unable to open $file for writing: $!");
    print {$fh} "Foo\n";
    close $fh;

    my $inode  = Archive::Tar::Builder::Inode->stat($file);
    my $header = Archive::Tar::Builder::Header->for_file(
        'file'        => $file,
        'member_name' => "foo-$file",
        'st'          => $inode,
        'user'        => 'foo',
        'group'       => 'bar'
    );

    ok( $header->file,     '$header->file() returns true on regular file' );
    ok( !$header->link,    '$header->link() returns false on regular file' );
    ok( !$header->symlink, '$header->symlink() returns false on regular file' );
    ok( !$header->char,    '$header->char() returns false on regular file' );
    ok( !$header->block,   '$header->block() returns false on regular file' );
    ok( !$header->dir,     '$header->dir() returns false on regular file' );
    ok( !$header->fifo,    '$header->fifo() returns false on regular file' );
    ok( !$header->contig,  '$header->contig() returns false on regular file' );

    my $encoded = $header->encode;

    test_header(
        $encoded,
        'path'          => "foo-$file",
        'mode'          => $inode->perm,
        'uid'           => $inode->[4],
        'gid'           => $inode->[5],
        'size'          => $inode->[7],
        'mtime'         => $inode->[9],
        'type'          => 0,
        'ustar'         => 'ustar',
        'ustar_version' => '00',
        'user'          => 'foo',
        'group'         => 'bar'
    );

    unlink($file);
}

# Test directories
{
    note('Testing directories');

    my $dir = "$tmpdir/dir";

    mkdir($dir) or die("Unable to mkdir() $dir: $!");

    my $inode  = Archive::Tar::Builder::Inode->stat($dir);
    my $header = Archive::Tar::Builder::Header->for_file(
        'file'        => $dir,
        'member_name' => "bar/$dir",
        'st'          => $inode
    );

    ok( $header->dir,      '$header->dir() returns true on directory' );
    ok( !$header->file,    '$header->file() returns false on directory' );
    ok( !$header->link,    '$header->link() returns false on directory' );
    ok( !$header->symlink, '$header->symlink() returns false on directory' );
    ok( !$header->char,    '$header->char() returns false on directory' );
    ok( !$header->block,   '$header->block() returns false on directory' );
    ok( !$header->fifo,    '$header->fifo() returns false on directory' );
    ok( !$header->contig,  '$header->contig() returns false on directory' );

    my $encoded = $header->encode;

    test_header(
        $encoded,
        'path'          => "bar/$dir",
        'mode'          => $inode->perm,
        'uid'           => $inode->[4],
        'gid'           => $inode->[5],
        'size'          => 0,
        'mtime'         => $inode->[9],
        'type'          => 5,
        'ustar'         => 'ustar',
        'ustar_version' => '00',
        'user'          => '',
        'group'         => ''
    );

    rmdir($dir);
}

# Test symbolic links
{
    my $symlink = "$tmpdir/bar";

    symlink( 'foo', $symlink ) or die("Unable to create symlink $symlink: $!");

    my $inode  = Archive::Tar::Builder::Inode->lstat($symlink);
    my $header = Archive::Tar::Builder::Header->for_file(
        'file'        => $symlink,
        'member_name' => "baz/$symlink",
        'st'          => $inode
    );

    ok( $header->symlink, '$header->symlink() returns true on symlink' );
    ok( !$header->file,   '$header->file() returns false on symlink' );
    ok( !$header->link,   '$header->link() returns false on symlink' );
    ok( !$header->dir,    '$header->dir() returns false on symlink' );
    ok( !$header->char,   '$header->char() returns false on symlink' );
    ok( !$header->block,  '$header->block() returns false on symlink' );
    ok( !$header->fifo,   '$header->fifo() returns false on symlink' );
    ok( !$header->contig, '$header->contig() returns false on symlink' );

    my $encoded = $header->encode;

    test_header(
        $encoded,
        'path'          => "baz/$symlink",
        'dest'          => 'foo',
        'mode'          => $inode->perm,
        'uid'           => $inode->[4],
        'gid'           => $inode->[5],
        'size'          => 0,
        'mtime'         => $inode->[9],
        'type'          => 2,
        'ustar'         => 'ustar',
        'ustar_version' => '00',
        'user'          => '',
        'group'         => ''
    );

    unlink($symlink);
}

# Test devices
{
    my %TESTS = (
        'char' => {
            'prefix'    => '',
            'suffix'    => 'null',
            'truncated' => 0,
            'mode'      => 0644,
            'uid'       => 0,
            'gid'       => 0,
            'size'      => 0,
            'mtime'     => time(),
            'linktype'  => 3,
            'linkdest'  => '',
            'user'      => '',
            'group'     => '',
            'major'     => 1,
            'minor'     => 3
        },

        'block' => {
            'prefix'    => '',
            'suffix'    => 'sda',
            'truncated' => 0,
            'mode'      => 0644,
            'uid'       => 0,
            'gid'       => 0,
            'size'      => 0,
            'mtime'     => time(),
            'linktype'  => 4,
            'linkdest'  => '',
            'user'      => '',
            'group'     => '',
            'major'     => 8,
            'minor'     => 0
        }
    );

    foreach my $type ( sort keys %TESTS ) {
        note("Testing $type devices");

        my $test    = $TESTS{$type};
        my $header  = bless $test, 'Archive::Tar::Builder::Header';
        my $encoded = $header->encode;

        test_header(
            $encoded,
            'major' => $test->{'major'},
            'minor' => $test->{'minor'}
        );
    }
}

# Test long pathnames with big components
{
    note('Testing ustar long pathname handling');

    #
    # Files
    #
    my $file        = "$tmpdir/foo";
    my $member_name = 'meow/' . 'foo' x 52;

    open( my $fh, '>', $file ) or die("Unable to open $file for writing: $!");
    print {$fh} "Meow\n";
    close $fh;

    my $inode  = Archive::Tar::Builder::Inode->stat($file);
    my $header = Archive::Tar::Builder::Header->for_file(
        'file'        => $file,
        'member_name' => $member_name,
        'st'          => $inode
    );

    my $encoded = $header->encode;

    test_header(
        $encoded,
        'path' => ( 'foo' x 31 ) . '7d5c2a2'
    );

    unlink($file);

    #
    # Directories
    #
    my $dir = "$tmpdir/cats";
    $member_name = ( 'foo' x 52 ) . '/' . ( 'bar' x 52 );

    mkdir($dir) or die("Unable to mkdir() $dir: $!");

    $inode  = Archive::Tar::Builder::Inode->stat($dir);
    $header = Archive::Tar::Builder::Header->for_file(
        'file'        => $dir,
        'member_name' => $member_name,
        'st'          => $inode
    );

    $encoded = $header->encode;

    test_header(
        $encoded,
        'path'   => ( 'bar' x 30 ) . 'ba886ae8',
        'prefix' => ( 'foo' x 32 )
    );

    rmdir($dir);
}

# Test GNU extensions
{
    note('Testing GNU extensions');

    my $dir = "$tmpdir/" . ( 'meow' x 32 ) . '/';

    mkdir($dir) or die("Unable to mkdir() $dir: $!");

    my $inode  = Archive::Tar::Builder::Inode->stat($dir);
    my $header = Archive::Tar::Builder::Header->for_file(
        'file'        => $dir,
        'member_name' => $dir,
        'st'          => $inode
    );

    my $encoded = $header->encode_gnu;

    test_header(
        $encoded,
        'path'          => '././@LongLink',
        'size'          => length($dir),
        'type'          => 'L',
        'ustar'         => 'ustar',
        'ustar_version' => '00'
    );

    is( substr( $encoded, 512, length($dir) ), $dir, '$header->encode_gnu() encodes long filename properly' );

    rmdir($dir);
}

# Test more $header->encode_gnu() behavior
{
    note('Testing further $header->encode_gnu() behavior');

    my $file = "$tmpdir/file";

    open( my $fh, '>', $file ) or die("Unable to open $file for writing: $!");
    print {$fh} "Foo\n";
    close $fh;

    my $inode  = Archive::Tar::Builder::Inode->stat($file);
    my $header = Archive::Tar::Builder::Header->for_file(
        'file'        => $file,
        'member_name' => "foo-$file",
        'st'          => $inode,
        'user'        => 'foo',
        'group'       => 'bar'
    );

    my $encoded = $header->encode_gnu;

    test_header(
        $encoded,
        'path'          => "foo-$file",
        'mode'          => $inode->perm,
        'uid'           => $inode->[4],
        'gid'           => $inode->[5],
        'size'          => $inode->[7],
        'mtime'         => $inode->[9],
        'type'          => 0,
        'ustar'         => 'ustar',
        'ustar_version' => '00',
        'user'          => 'foo',
        'group'         => 'bar'
    );

    unlink($file);
}

# Test >8GB file size support
{
    my $header = bless {
        'prefix'    => '',
        'suffix'    => 'reallybigfile',
        'truncated' => 0,
        'mode'      => 0644,
        'uid'       => 0,
        'gid'       => 0,
        'size'      => 1048576 * 1024 * 8,
        'mtime'     => time(),
        'linktype'  => 0,
        'linkdest'  => '',
        'user'      => '',
        'group'     => '',
        'major'     => 0,
        'minor'     => 0
      },
      'Archive::Tar::Builder::Header';

    throws_ok {
        $header->encode;
    }
    qr/Cannot archive files >8GB; please use GNU extensions to overcome this limitation/, '$header->encode() fails when file larger than 8GB without GNU extensions';

    my $encoded;

    lives_ok {
        $encoded = $header->encode( 'gnu_extensions' => 1 );
    }
    '$header->encode() succeeds when "gnu_extensions" option set';

    my $found = substr( $encoded, 124, 12 );
    my $expected = "\x80\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00";

    ok( $found eq $expected, '$header->encode() properly encodes base256 size value' );

    #
    # Test that size values are not encoded differently when the size is less than 8GB.
    #
    $header->{'size'} = ( 1048576 * 1024 * 8 ) - 1;

    $encoded = $header->encode( 'gnu_extensions' => 1 );

    $found = int( substr( $encoded, 124, 1 ) ) & 0x80;

    ok( !$found, '$header->encode() does not use base 256 encoding for >8GB files in GNU mode' );
}
