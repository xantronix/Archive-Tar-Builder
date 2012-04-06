# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

package Archive::Tar::Builder;

use strict;
use warnings;

use Archive::Tar::Builder::Bits;
use Archive::Tar::Builder::Header ();
use Archive::Tar::Builder::Inode  ();
use Archive::Tar::Builder::Match  ();

use File::Find ();
use File::Spec ();

=head1 NAME

Archive::Tar::Builder - Stream tarball data to a file handle

=head1 DESCRIPTION

Archive::Tar::Builder is meant to quickly and easily generate tarball streams,
and write them to a given file handle.  Though its options are few, its flexible
interface provides for a number of possible uses in many scenarios.

Archive::Tar::Builder supports path inclusions and exclusions (implemented in C
for speed), arbitrary file name length, and the ability to add items from the
filesystem into the archive under an arbitrary name.

=cut

BEGIN {
    use Exporter ();
    our $VERSION = '0.3';
}

our $BLOCK_SIZE = 512;

=head1 CONSTRUCTOR

=over

=item C<Archive::Tar::Builder-E<gt>new(%opts)>

Create a new Archive::Tar::Builder object.  Available options are:

=over

=item B<gnu_extensions>

Set to a true value to enable use of GNU extensions, namely support for
arbitrarily long filenames.

=back

=back

=cut

sub new {
    my ( $class, %opts ) = @_;

    return bless {
        'gnu_extensions' => $opts{'gnu_extensions'},
        'match'          => Archive::Tar::Builder::Match->new,
        'use_exclusions' => 0,
        'members'        => [],
        'uidcache'       => {},
        'gidcache'       => {}
    }, $class;
}

sub _lookup_user {
    my ( $self, $uid, $gid ) = @_;

    unless ( exists $self->{'uidcache'}->{$uid} ) {
        if ( my @pwent = getpwuid($uid) ) {
            $self->{'uidcache'}->{$uid} = $pwent[0];
        }
        else {
            $self->{'uidcache'}->{$uid} = undef;
        }
    }

    unless ( exists $self->{'gidcache'}->{$gid} ) {
        if ( my @grent = getgrgid($gid) ) {
            $self->{'gidcache'}->{$gid} = $grent[0];
        }
        else {
            $self->{'gidcache'}->{$gid} = undef;
        }
    }

    return ( $self->{'uidcache'}->{$uid}, $self->{'gidcache'}->{$gid} );
}

sub _write_file {
    my ( $self, %args ) = @_;

    open( my $fh, '<', $args{'file'} ) or die("Unable to open $args{'file'} for reading: $!");

    while ( my $len = read( $fh, my $buf, 4096 ) ) {
        if ( ( my $padlen = $BLOCK_SIZE - ( $len % $BLOCK_SIZE ) ) != $BLOCK_SIZE ) {
            $len += $padlen;
            $buf .= "\x0" x $padlen;
        }

        print { $args{'handle'} } $buf;
    }

    close $fh;

    return;
}

sub _archive {
    my ( $self, %args ) = @_;
    my ( $user, $group ) = $self->_lookup_user( $args{'st'}->[4], $args{'st'}->[5] );

    my $header = Archive::Tar::Builder::Header->for_file(
        'st'          => $args{'st'},
        'file'        => $args{'file'},
        'member_name' => $args{'member_name'},
        'user'        => $user,
        'group'       => $group
    );

    my $blocks = $self->{'gnu_extensions'} ? $header->encode_gnu : $header->encode;

    print { $args{'handle'} } $blocks;

    $self->_write_file(
        'file'   => $args{'file'},
        'handle' => $args{'handle'}
    ) if $args{'st'}->file;
}

=head1 ADDING MEMBERS TO ARCHIVE

=over

=item C<$archive-E<gt>add_as(%members)>

Add any number of members to the current archive, where the keys specified in
C<%members> specify the paths where the files exist on the filesystem, and the
values shall represent the eventual names of the members as they shall be
written upon archive writing.

=cut

sub add_as {
    my ( $self, %members ) = @_;

    foreach my $file ( sort keys %members ) {
        my $member_name = $members{$file};

        push @{ $self->{'members'} }, [ $file => $member_name ];
    }

    return;
}

=item C<$archive->E<gt>add(@files)>

Add any number of members to the current archive.

=back

=cut

sub add {
    my ( $self, @files ) = @_;

    foreach my $file (@files) {
        push @{ $self->{'members'} }, [ $file => $file ];
    }

    return;
}

=head1 FILE PATH MATCHING

File path matching facilities exist to control, based on filenames and patterns,
which data should be included into and excluded from an archive made up of a
broad selection of files.

Note that file pattern matching operations triggered by usage of inclusions and
exclusions are performed against the names of the members of the archive as they
are added to the archive, not as the names of the files as they live in the
filesystem.

=head2 FILE PATH INCLUSIONS

File inclusions can be used to specify patterns which name members that should
be included into an archive, to the exclusion of other members.  File inclusions
take lower precedence to L<exclusions|FILE PATH EXCLUSIONS>.

=over

=item C<$archive-E<gt>include($pattern)>

Add a file match pattern, whose format is specified by fnmatch(3), for which
matching member names should be included into the archive.  Will die() upon
error.

=cut

sub include {
    my ( $self, $pattern ) = @_;
    $self->{'use_exclusions'} = 1;

    return $self->{'match'}->include($pattern);
}

=item C<$archive-E<gt>include_from_file($file)>

Import a list of file inclusion patterns from a flat file consisting of newline-
separated patterns.  Will die() upon error, especially failure to open a file
for reading inclusion patterns.

=back

=cut

sub include_from_file {
    my ( $self, $file ) = @_;
    $self->{'use_exclusions'} = 1;

    return $self->{'match'}->include_from_file($file);
}

=head2 FILE PATH EXCLUSIONS

=over

=item C<$archive-E<gt>exclude($pattern)>

Add a pattern which specifies that an exclusion of files and directories with
matching names should be excluded from the archive.  Note that exclusions take
higher priority than inclusions.  Will die() upon error.

=cut

sub exclude {
    my ( $self, $pattern ) = @_;
    $self->{'use_exclusions'} = 1;

    return $self->{'match'}->exclude($pattern);
}

=item C<$archive-E<gt>exclude_from_file($file)>

Add a number of patterns from a flat file consisting of exclusion patterns
separated by newlines.  Will die() upon error, especially when unable to open a
file for reading.

=back

=cut

sub exclude_from_file {
    my ( $self, $file ) = @_;
    $self->{'use_exclusions'} = 1;

    return $self->{'match'}->exclude_from_file($file);
}

=head2 TESTING EXCLUSIONS

=over

=item C<$archive-E<gt>is_excluded($path)>

Based on the file exclusion and inclusion patterns (respectively), determine if
the given path is to be excluded from the archive upon writing.

=back

=cut

sub is_excluded {
    my ( $self, $path ) = @_;

    return $self->{'match'}->is_excluded($path);
}

=head1 WRITING ARCHIVE DATA

=over

=item C<$archive-E<gt>start($handle)>

Write a tar stream of either ustar (default) or GNU tar format (optional), with
files excluded based on any possible previous usage of the filename inclusion
and exclusion calls.  Members will be written with the names given to them when
they were originally added to the archive for writing.

=back

=cut

sub start {
    my ( $self, $handle ) = @_;

    foreach my $member ( @{ $self->{'members'} } ) {
        my ( $file, $member_name ) = map { File::Spec->canonpath($_) } @{$member};

        File::Find::find(
            {
                'no_chdir' => 1,
                'wanted'   => sub {
                    my $new_member_name = $File::Find::name;

                    if ( $file ne $member_name ) {
                        $new_member_name =~ s/^$file/$member_name/;
                    }

                    #
                    # Only test to see if the current member is excluded if any
                    # exclusions or inclusions were actually specified, to save
                    # time calling the exclusion engine.
                    #
                    if ( $self->{'use_exclusions'} ) {
                        return if $self->is_excluded($new_member_name);
                    }

                    my %args = (
                        'st'          => Archive::Tar::Builder::Inode->lstat($File::Find::name),
                        'file'        => $File::Find::name,
                        'member_name' => $new_member_name
                    );

                    $self->_archive(
                        %args,
                        'handle' => $handle
                    );
                  }
            },
            $file
        );
    }
}

1;

__END__

=head1 COPYRIGHT

Copyright (c) 2012, cPanel, Inc.
All rights reserved.
http://cpanel.net/

This is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.  See L<perlartistic> for further details.
