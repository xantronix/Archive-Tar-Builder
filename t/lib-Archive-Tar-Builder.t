#!/usr/bin/perl

# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

use strict;
use warnings;

use ExtUtils::testlib;

use Cwd        ();
use File::Temp ();
use File::Path ();
use IPC::Open3 ();
use Symbol     ();

use Archive::Tar::Builder ();

use Test::More ( 'tests' => 44 );

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
    my $reader_pid = IPC::Open3::open3( my ( $in, $out ), undef, $tar, '-tf', '-' );
    my $writer_pid = fork();

    if ( !defined $writer_pid ) {
        die("Unable to fork(): $!");
    }
    elsif ( $writer_pid == 0 ) {
        close $out;
        $archive->write($in);

        #
        # This may seem a bit gratuitous, but this is needed because Perl 5.6.2's
        # distribution of File::Temp has a bug in which directories are cleaned
        # up regardless if the process exiting is a child of the process that
        # created the directory in question, or not.  execve() is the easiest way
        # to clear away atexit() handlers in this case.
        #
        exec( '/bin/sh', '-c', 'true' );
    }

    close $in;

    my %EXPECTED = map { $_ => 1 } qw(
      foo/
      foo/exclude.txt
      foo/bar/
      foo/poop/
      bar/
      bar/exclude.txt
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

    my %statuses = map {
        waitpid( $_, 0 );
        $_ => $? >> 8;
    } ( $writer_pid, $reader_pid );

    is( $found, $entries, '$archive->write() wrote the appropriate number of items' );
    is( $statuses{$writer_pid} => 0, '$archive->write() subprocess exited with 0 status' );
    is( $statuses{$reader_pid} => 0, 'tar subprocess exited with 0 status' );

    #
    # Exercise $archive->write() in the parent process; we cannot capture output
    # if we are to do this reliably.
    #
    pipe my $in_read, $in or die("Unable to pipe(): $!");

    my $pid = fork();

    if ( !defined $pid ) {
        die("Unable to fork(): $!");
    }
    elsif ( $pid == 0 ) {
        close $in;

        open( STDIN,  '<&=' . fileno($in_read) );
        open( STDOUT, '>/dev/null' );
        exec( $tar, '-tf', '-' ) or die("Unable to exec() $tar: $!");
    }

    close $in_read;

    eval { $archive->write($in); };

    is( $@ => '', '$archive->write() does not die when writing to handle' );

    close $in;
    waitpid( $pid, 0 );

    is( ( $? >> 8 ) => 0, 'tar exited with a zero status' );

    # Need to do this otherwise the atexit() handler File::Temp sets up won't work
    chdir($oldpwd) or die("Unable to chdir() to $oldpwd: $!");
}

# Test inclusion
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

# Test exclusions
{
    my $archive = Archive::Tar::Builder->new;

    eval { $archive->exclude('excluded'); };

    is( $@ => '', '$archive->exclude() does not die' );

    my $badfile = '/dev/null/impossible';
    my ( $fh, $file ) = File::Temp::tempfile();
    print {$fh} "skipped\n";
    print {$fh} "unwanted\n";
    print {$fh} "ignored\n";
    print {$fh} "backup-[!_]*_[!-]*-[!-]*-[!_]*_foo*\n";
    close $fh;

    eval { $archive->exclude_from_file($file); };

    is( $@ => '', '$archive->exclude_from_file() does not die when given a good file' );

    eval { $archive->exclude_from_file($badfile); };

    like( $@ => qr/Cannot add items to exclusion list from file $badfile:/, '$archive->exclude_from_file() dies when unable to read file' );

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

    print '# Excluding: "excluded", "skipped", "unwanted", "ignored"' . "\n";

    foreach my $test ( sort keys %TESTS ) {
        my $expected = $TESTS{$test};

        if ( $archive->is_excluded($test) ) {
            ok( !$expected, "Path '$test' is excluded" );
        }
        else {
            ok( $expected, "Path '$test' is NOT excluded" );
        }
    }

    unlink($file);
}

# Further test inclusions
{
    my $archive = Archive::Tar::Builder->new;

    print '# Using "foo", "bar", "baz" and "meow" as inclusions' . "\n";

    my $badfile = '/dev/null/impossible';
    my ( $fh, $file ) = File::Temp::tempfile();
    print {$fh} "foo\n";
    print {$fh} "bar\n";
    print {$fh} "baz\n";
    close $fh;

    eval { $archive->include('meow'); };

    is( $@ => '', '$archive->include() does not die when adding inclusion pattern' );

    eval { $archive->include_from_file($badfile); };

    like( $@ => qr/^Cannot add items to inclusion list from file $badfile:/, '$archive->include_from_file() dies on invalid file' );

    eval { $archive->include_from_file($file); };

    is( $@ => '', '$archive->include_from_file() does not die when adding include patterns from file' );

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
            ok( !$archive->is_excluded($path), "'$path' is included" );
        }
        else {
            ok( $archive->is_excluded($path), "'$path' is not included" );
        }
    }

    unlink($file);
}

# Test long filenames, symlinks
{
    my $tmpdir = File::Temp::tempdir( 'CLEANUP' => 1 );
    my $path = "$tmpdir/" . ( 'foops/' x 50 );

    File::Path::mkpath($path) or die("Unable to create long path: $!");

    symlink( 'foo', "$tmpdir/bar" ) or die("Unable to symlink() $tmpdir/bar to foo: $!");

    my $archive = Archive::Tar::Builder->new;
    $archive->add($tmpdir);

    my $err = Symbol::gensym();

    my $reader_pid = IPC::Open3::open3( my ( $in, $out ), $err, $tar, '-tf', '-' );
    my $writer_pid = fork();

    if ( !defined $writer_pid ) {
        die("Unable to fork(): $!");
    }
    elsif ( $writer_pid == 0 ) {
        $archive->write($in);
        exec( '/bin/sh', '-c', 'true' );
    }

    my ( $paths, $errors );

    my $rin = '';
    vec( $rin, fileno($out), 1 ) = 1;
    vec( $rin, fileno($err), 1 ) = 1;

    my %FOUND = (
        $path         => 0,
        "$tmpdir/bar" => 0
    );

    close $in;

    while ( select( my $rout = $rin, undef, undef, undef ) > 0 ) {
        my $buf;
        my $len;

        if ( vec( $rout, fileno($out), 1 ) ) {
            $len = sysread( $out, $buf, 512 );

            if ( !$len ) {
                vec( $rin, fileno($out), 1 ) = 0;
            }
            else {
                $paths .= $buf;
            }
        }

        if ( vec( $rout, fileno($err), 1 ) ) {
            $len = sysread( $err, $buf, 512 );

            if ( !$len ) {
                vec( $rin, fileno($err), 1 ) = 0;
            }
            else {
                $errors .= $buf;
            }
        }

        last unless grep { $_ } unpack( 'C*', $rin );
    }

    foreach my $item ( split "\n", $paths ) {
        $FOUND{$item} = 1;
    }

    close $err;
    close $out;

    my %statuses = map {
        waitpid( $_, 0 );
        $_ => $? >> 8;
    } ( $reader_pid, $writer_pid );

    foreach my $item ( split "\n", $errors ) {
        diag("From standard error: $item");
    }

    is( $statuses{$writer_pid} => 0, '$archive->write() did not die while archiving long pathnames' );
    is( $statuses{$reader_pid} => 0, 'tar -tf - did not die while parsing tar stream with long pathnames' );
    ok( $FOUND{$path},         "\$archive->write() properly encoded a long pathname for directory for $path" );
    ok( $FOUND{"$tmpdir/bar"}, '$archive->write properly encoded a symlink' );
}
