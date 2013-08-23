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

use lib "lib";
use Archive::Tar::Builder ();

# This is a good test to run, but it has the potential to be disruptive, so
# only run it internally or if someone explicitly requests it.
if ( $ENV{TEST_BIGFILE} || `hostname` =~ /cpanel/ ) {
    plan tests => 2;
}
else {
    plan skip_all => "$0 is a fairly resource-intensive test that creates a 2.5 GB file and must be run with the environment variable TEST_BIGFILE=1 if you really want to test this functionality.";
}

my $big_file_name = '2.5_GB_file';

# A sparse file, but still triggers the problem without the case 71041 fix
open my $fh, '>', $big_file_name;
seek $fh, 2.5 * 2**30, 0;
truncate $fh, tell($fh);
close $fh;

my $size = ( stat $big_file_name )[7];
is $size, 2684354560, "$big_file_name was created with proper size"
  or die "$big_file_name could not be created, so the test will not be effective";

# Case 71041
lives_ok {
    my $atb = Archive::Tar::Builder->new();
    open my $null, ">", "/dev/null";
    $atb->set_handle($null);
    $atb->archive($big_file_name);
    $atb->finish;
    close $null;
}
'Archive::Tar::Builder can handle a 2.5 GB file';

unlink $big_file_name;
