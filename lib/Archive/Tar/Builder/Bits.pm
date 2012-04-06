# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

package Archive::Tar::Builder::Bits;

use strict;
use warnings;

BEGIN {
    use Exporter ();
    use vars qw/@ISA @EXPORT/;

    @ISA = qw/Exporter/;

    @EXPORT = qw(
      $S_IFMT
      $S_IFIFO $S_IFCHR $S_IFDIR $S_IFBLK $S_IFREG $S_IFLNK $S_IFSOCK
      $S_IFWHT $S_IPROT $S_ISUID $S_ISGID $S_ISVTX $S_IPERM $S_IRWXU
      $S_IRUSR $S_IWUSR $S_IXUSR $S_IRWXG $S_IRGRP $S_IWGRP $S_IXGRP
      $S_IRWXO $S_IROTH $S_IWOTH $S_IXOTH $S_IRW $S_IR $S_IW $S_IX
    );
}

=head1 NAME

Archive::Tar::Builder::Bits - Bitfield and constant definitions for file modes

=head1 DESCRIPTION

This file contains all the constant definitions for the inode mode bitfields and
values.

=cut

#
# Inode format bitfield and values
#
our $S_IFMT = 0170000;

our $S_IFIFO  = 0010000;
our $S_IFCHR  = 0020000;
our $S_IFDIR  = 0040000;
our $S_IFBLK  = 0060000;
our $S_IFREG  = 0100000;
our $S_IFLNK  = 0120000;
our $S_IFSOCK = 0140000;
our $S_IFWHT  = 0160000;

#
# Inode execution protection bitfield and values
#
our $S_IPROT = 0007000;

our $S_ISUID = 0004000;
our $S_ISGID = 0002000;
our $S_ISVTX = 0001000;

#
# Inode permission bitfield and values
#
our $S_IR    = 0000444;
our $S_IW    = 0000222;
our $S_IX    = 0000111;
our $S_IRW   = $S_IR | $S_IW;
our $S_IPERM = $S_IRW | $S_IX;

# Per assigned user
our $S_IRWXU = 0000700;

our $S_IRUSR = 0000400;
our $S_IWUSR = 0000200;
our $S_IXUSR = 0000100;

# Per assigned group
our $S_IRWXG = 0000070;

our $S_IRGRP = 0000040;
our $S_IWGRP = 0000020;
our $S_IXGRP = 0000010;

# All other users
our $S_IRWXO = 0000007;

our $S_IROTH = 0000004;
our $S_IWOTH = 0000002;
our $S_IXOTH = 0000001;

1;
