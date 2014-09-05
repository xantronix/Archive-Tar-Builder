#!/usr/bin/perl

# Copyright (c) 2013, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

use strict;
use warnings;

use ExtUtils::testlib;
use Test::More;
use Test::Exception;
use autodie;

use Fcntl qw(O_WRONLY O_CREAT O_APPEND O_LARGEFILE SEEK_CUR);
use IPC::Open3 ();

use lib "lib";
use Archive::Tar::Builder ();

my @file_sizes = (
    2 * 2**30,      # 2 GiB
    4 * 2**30,      # 4 GiB
    8 * 2**30,      # 8 GiB
    8.5 * 2**30,    # 8.5 GiB
);

my $file_created = 0;

#
# This is a good test to run, but it has the potential to be disruptive, so
# only run it if someone explicitly requests it
#
if ( $ENV{TEST_BIGFILE} ) {
    plan tests => 3 * @file_sizes;
}
else {
    plan skip_all => "Big-file tests disabled unless TEST_BIGFILE environment variable is set.";
    exit 0;
}

my $file_name = 'large_file';

# Cleanup code
END { unlink $file_name if $file_created }
$SIG{INT} = sub { exit };

foreach my $size (@file_sizes) {
    create_file( $file_name, $size );
    $file_created = 1;
    test_large_file( $file_name, $size );
}

exit 0;

sub test_large_file {
    my ( $file_name, $file_size ) = @_;

    my $hrsize = human_readable_file_size($file_size);

  SKIP: {
        my $stat_size = ( stat $file_name )[7];
        is $stat_size, $file_size, "$file_name was created with proper size ($hrsize)"
          or skip "$file_name could not be created, so the test will not be effective", 2;

        my ( $to_tar, $tar_outerr );
        my $pid = IPC::Open3::open3( $to_tar, $tar_outerr, 0, 'tar', '-t' );

        # Case 71041
        lives_ok {
            my $atb = Archive::Tar::Builder->new();
            $atb->set_handle($to_tar);
            $atb->archive($file_name);
            $atb->finish;
        }
        "Archive::Tar::Builder can handle a $hrsize large file";

        my $out = '';
        while (<$tar_outerr>) {
            $out .= $_;
        }

        # Case 80933
        is $out, $file_name . "\n", "System tar reports no errors when reading tarball containing $hrsize large file"
          or diag $out;

        # Reap child process
        waitpid $pid, 0;
    }
}

sub systell { sysseek( $_[0], 0, SEEK_CUR ) }

sub create_file {
    my ( $file_name, $file_size ) = @_;

    sysopen( my $fh, $file_name, O_WRONLY | O_CREAT | O_APPEND | O_LARGEFILE );
    my $write_size = $file_size - systell($fh);

    if ( $write_size > 0 ) {
        my $block_size = 1024 * 1024;
        my $buffer     = "1" x $block_size;

        my $block_count = int( $write_size / $block_size );
        my $remainder   = int( $write_size % $block_size );

        for ( 1 .. $block_count ) {
            syswrite( $fh, $buffer, $block_size );
        }
        if ($remainder) {
            syswrite( $fh, $buffer, $remainder );
        }
    }

    truncate $fh, $file_size;
    close $fh;
}

sub human_readable_file_size {
    my ($file_size) = @_;

    my @suffix       = qw(bytes KiB MiB GiB TiB PiB EiB ZiB YiB);
    my $suffix_index = 0;

    while ( $file_size >= 1024 ) {
        $file_size /= 1024;
        ++$suffix_index;
    }

    die "Number too large: $file_size * 1024**$suffix_index" if $suffix_index >= @suffix;

    return sprintf( "%.1f %s", $file_size, $suffix[$suffix_index] );
}
