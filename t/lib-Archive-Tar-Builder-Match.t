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
use Test::More ( 'tests' => 29 );

use File::Temp ();

use Archive::Tar::Builder::Match ();

# Test exclusions
{
    my $match;

    # I guess this test is a bit silly, since we can't trap segfaults like this so
    # easily...
    lives_ok {
        $match = Archive::Tar::Builder::Match->new;
    }
    'Archive::Tar::Builder::Match->new() lives on instantiation';

    isa_ok( $match => 'Archive::Tar::Builder::Match', '$match' );

    # At least we can test the destructor in some meaningful way.
    lives_ok {
        my $match = Archive::Tar::Builder::Match->new;

        #
        # We can't call $match->DESTROY() directly, unless we want to possibly see
        # a glibc stack trace on a double free(), or a segfault, or worse...
        #
        undef $match;
    }
    '$match->DESTROY() seems to work';

    lives_ok {
        $match->exclude('excluded');
    }
    '$match->exclude() does not die';

    my $badfile = '/dev/null/impossible';
    my ( $fh, $file ) = File::Temp::tempfile();
    print {$fh} "skipped\n";
    print {$fh} "unwanted\n";
    print {$fh} "ignored\n";
    print {$fh} "backup-[!_]*_[!-]*-[!-]*-[!_]*_foo*\n";
    close $fh;

    lives_ok {
        $match->exclude_from_file($file);
    }
    '$match->exclude_from_file() does not die when given a good file';

    throws_ok {
        $match->exclude_from_file($badfile);
    }
    qr/Cannot add items to exclusion list from file $badfile:/, '$match->exclude_from_file() dies when unable to read file';

    my %TESTS = (
        'foo/bar/baz'                                    => 1,
        'cats/meow'                                      => 1,
        'this/is/allowed'                                => 1,
        'meow/excluded/really'                           => 0,
        'meow/excluded'                                  => 0,
        'poop/skipped/meow'                              => 0,
        'poop/skipped'                                   => 0,
        'bleh/unwanted'                                  => 0,
        'bleh/ignored/meow'                              => 0,
        'bleh/ignored'                                   => 0,
        '/home/backup-4.5.2012_12-10-36_foo.tar.gz/cats' => 0,
        '/home/backup-4.5.2012_12-10-36_foo.tar.gz'      => 0,
        '/home/backu-4.5.2012_12-10-36_foo.tar.gz'       => 1
    );

    note('Excluding: "excluded", "skipped", "unwanted", "ignored"');

    foreach my $test ( sort keys %TESTS ) {
        my $expected = $TESTS{$test};

        if ( $match->is_excluded($test) ) {
            ok( !$expected, "Path '$test' is excluded" );
        }
        else {
            ok( $expected, "Path '$test' is NOT excluded" );
        }
    }

    unlink($file);
}

# Test inclusions
{
    my $match = Archive::Tar::Builder::Match->new;

    note('Using "foo", "bar", "baz" and "meow" as inclusions');

    my $badfile = '/dev/null/impossible';
    my ( $fh, $file ) = File::Temp::tempfile();
    print {$fh} "foo\n";
    print {$fh} "bar\n";
    print {$fh} "baz\n";
    close $fh;

    lives_ok {
        $match->include('meow');
    }
    '$match->include() does not die when adding inclusion pattern';

    throws_ok {
        $match->include_from_file($badfile);
    }
    qr/^Cannot add items to inclusion list from file $badfile:/, '$match->include_from_file() dies on invalid file';

    lives_ok {
        $match->include_from_file($file);
    }
    '$match->include_from_file() does not die when adding include patterns from file';

    my %TESTS = (
        'foo'          => 1,
        'bar/poo'      => 1,
        'baz/poo'      => 1,
        'meow/cats'    => 1,
        'haz/meow/poo' => 0,
        'haz/poo/meow' => 0,
        'bleh'         => 0
    );

    foreach my $path ( sort keys %TESTS ) {
        my $should_be_included = $TESTS{$path};

        if ($should_be_included) {
            ok( !$match->is_excluded($path), "'$path' is included" );
        }
        else {
            ok( $match->is_excluded($path), "'$path' is not included" );
        }
    }

    unlink($file);
}
