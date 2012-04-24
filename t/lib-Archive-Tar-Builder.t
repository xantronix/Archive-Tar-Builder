#!/usr/bin/perl

# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

use strict;
use warnings;

use Cwd           ();
use File::Temp    ();
use File::Path    ();
use IPC::Pipeline ();

use Archive::Tar::Builder ();

use Test::Exception;
use Test::More ( 'tests' => 21 );

sub find_tar {
    my @PATHS    = qw( /bin /usr/bin /usr/local/bin );
    my @PROGRAMS = qw( bsdtar tar gtar );

    foreach my $path (@PATHS) {
        foreach my $program (@PROGRAMS) {
            my $name = "$path/$program";

            return $name if -x $name;
        }
    }

    die('Could not locate a tar binary');
}

sub find_unused_ids {
    my ( $uid, $gid );

    for ( $uid = 99999; getpwuid($uid); $uid-- ) { }
    for ( $gid = 99999; getgrgid($gid); $gid-- ) { }

    return ( $uid, $gid );
}

sub build_tree {
    my $tmpdir = File::Temp::tempdir( 'CLEANUP' => 1 );
    my $file = "$tmpdir/foo/exclude.txt";

    File::Path::mkpath("$tmpdir/foo/bar/baz/foo/cats");
    File::Path::mkpath("$tmpdir/foo/poop");
    File::Path::mkpath("$tmpdir/foo/cats/meow");

    open( my $fh, '>', $file ) or die("Unable to open $file for writing: $!");
    print {$fh} "cats\n";
    close $fh;

    my $long   = 'bleh' x 50;
    my $subdir = "$tmpdir/$long/$long";
    $file = "$subdir/thingie.txt";

    File::Path::mkpath($subdir);

    open( $fh, '>', $file ) or die("Unable to open $file for writing: $!");
    print {$fh} "Meow\n";
    close $fh;

    return $tmpdir;
}

my $badfile = '/dev/null/impossible';
my $tar     = find_tar();

#
# Test Archive::Tar::Builder internal methods
#
{
    my $archive = Archive::Tar::Builder->new;

    my ( $unused_uid, $unused_gid ) = find_unused_ids();

    #
    # Test $archive->_lookup_user()
    #
    my ( $root_name,   $root_group )   = $archive->_lookup_user( 0,           0 );
    my ( $unused_name, $unused_group ) = $archive->_lookup_user( $unused_uid, $unused_gid );

    #
    # I realize some stupid systems may actually not name root, 'root'...
    # I'm looking at you, OS X with your Directory Services...
    #
    # The root group name isn't frequently 'root' outside of the Linux circles,
    # by the by.
    #
    like( $root_name => qr/^(_|)root$/, '$archive->_lookup_user() can locate known existing user name' );
    ok( defined $root_group, '$archive->_lookup_user() can locate known existing group name ' . "'$root_group'" );

    ok( !defined($unused_name),  '$archive->_lookup_user() returns undef on unknown UID' );
    ok( !defined($unused_group), '$archive->_lookup_user() returns undef on unknown GID' );

    #
    # Test $archive->_write_file()
    #
    throws_ok {
        $archive->_write_file(
            'file'   => $badfile,
            'handle' => \*STDOUT
        );
    }
    qr/^Unable to open $badfile for reading:/, '$archive->_write_file() dies when passed a bad file';
}

#
# Test external functionality
#
{
    my $oldpwd = Cwd::getcwd();
    my $tmpdir = build_tree();

    chdir($tmpdir) or die("Unable to chdir() to $tmpdir: $!");

    my $archive = Archive::Tar::Builder->new;

    $archive->add('foo');
    $archive->add_as( 'foo' => 'bar' );
    $archive->add_as( 'foo' => 'baz' );

    #
    # Test Archive::Tar::Builder's ability to exclude files
    #
    $archive->exclude_from_file("$tmpdir/foo/exclude.txt");
    $archive->exclude('baz');

    ok( $archive->is_excluded("$tmpdir/baz"),           '$archive->is_excluded() works when excluding added with $archive->exclude()' );
    ok( $archive->is_excluded("$tmpdir/foo/cats/meow"), '$archive->is_excluded() works when exclusion added with $archive->exclude_from_file()' );

    #
    # Test to see the expected contents are written.
    #
    my %statuses;
    my @pids = IPC::Pipeline::pipeline(
        undef,
        my $out,
        undef,
        sub {
            $archive->start( \*STDOUT );
            exit 0;
        },

        [ $tar, '-tf', '-' ]
    );

    my %EXPECTED = map { $_ => 1 } qw(
      foo/
      foo/bar/
      foo/poop/
      bar/
      bar/bar/
      bar/poop/
    );

    my $entries    = scalar keys %EXPECTED;
    my $found      = 0;
    my $unexpected = 0;

    while ( my $line = readline($out) ) {
        chomp $line;

        if ( $EXPECTED{$line} ) {
            delete $EXPECTED{$line};
            $found++;
        }
        else {
            $unexpected++;
        }
    }

    close $out;

    foreach my $pid (@pids) {
        waitpid( $pid, 0 );
        $statuses{$pid} = $? >> 8;
    }

    is( $found, $entries, '$archive->start() wrote the appropriate number of items' );
    is( $statuses{ $pids[0] } => 0, '$archive->start() subprocess exited with 0 status' );
    is( $statuses{ $pids[1] } => 0, 'tar subprocess exited with 0 status' );

    #
    # Exercise $archive->start() in the parent process; we cannot capture output
    # if we are to do this reliably.
    #
    my ($pid) = IPC::Pipeline::pipeline(
        my $in,
        undef, undef,
        sub {
            open( STDOUT, '>/dev/null' );
            exec( $tar, '-tf', '-' );
            exit 127;
        }
    );

    lives_ok {
        $archive->start($in);
    }
    '$archive->start() does not die when writing to handle';

    close $in;
    waitpid( $pid, 0 );

    is( ( $? >> 8 ) => 0, 'tar exited with a zero status' );

    # Need to do this otherwise the atexit() handler File::Temp sets up won't work
    chdir($oldpwd) or die("Unable to chdir() to $oldpwd: $!");
}

#
# Test GNU extensions
#
{
    my $oldpwd = Cwd::getcwd();
    my $tmpdir = build_tree();

    chdir($tmpdir) or die("Unable to chdir() to $tmpdir: $!");

    my $archive = Archive::Tar::Builder->new( 'gnu_extensions' => 1 );

    $archive->add('foo');

    my ($pid) = IPC::Pipeline::pipeline(
        my $in,
        undef, undef,
        sub {
            open( STDOUT, '>/dev/null' );
            exec( $tar, '-tf', '-' );
            exit 127;
        }
    );

    lives_ok {
        $archive->start($in);
    }
    '$archive->start() does not die when archiving with GNU extensions on';

    close $in;
    waitpid( $pid, 0 );

    is( ( $? >> 8 ) => 0, 'tar exited with a nonzero status' );

    chdir($oldpwd) or die("Unable to chdir() to $oldpwd: $!");
}

#
# Test inclusion (more tests in t-Archive-Tar-Builder-Match.t)
#
{
    my $archive = Archive::Tar::Builder->new;

    my ( $fh, $file ) = File::Temp::tempfile();
    print {$fh} "feh\n";
    print {$fh} "moo/*\n";
    close $fh;

    $archive->include('cats/*');
    $archive->include_from_file($file);

    my %TESTS = (
        'foo/bar/baz/foo/cats' => 0,
        'cats/meow'            => 1,
        'bleh/poo'             => 0,
        'thing/feh'            => 0,
        'feh/thing'            => 1,
        'hrm/moo'              => 0,
        'moo/hrm'              => 1
    );

    foreach my $path ( sort keys %TESTS ) {
        my $should_be_included = $TESTS{$path};

        if ($should_be_included) {
            ok( !$archive->is_excluded($path), "Path '$path' is included" );
        }
        else {
            ok( $archive->is_excluded($path), "Path '$path' is included" );
        }
    }
}
