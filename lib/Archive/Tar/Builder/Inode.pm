# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

package Archive::Tar::Builder::Inode;

use strict;
use warnings;

use Archive::Tar::Builder::Bits;

sub stat {
    my ( $class, $file ) = @_;
    my @st = stat($file) or die("Unable to stat() $file: $!");

    return bless \@st, $class;
}

sub lstat {
    my ( $class, $file ) = @_;
    my @st = lstat($file) or die("Unable to lstat() $file: $!");

    return bless \@st, $class;
}

sub mode {
    return shift->[2];
}

sub fmt {
    return shift->[2] & $S_IFMT;
}

sub perm {
    return shift->[2] & $S_IPERM;
}

sub file {
    return ( shift->[2] & $S_IFMT ) == $S_IFREG;
}

sub dir {
    return ( shift->[2] & $S_IFMT ) == $S_IFDIR;
}

sub link {
    return ( shift->[2] & $S_IFMT ) == $S_IFLNK;
}

sub char {
    return ( shift->[2] & $S_IFMT ) == $S_IFCHR;
}

sub block {
    return ( shift->[2] & $S_IFMT ) == $S_IFBLK;
}

sub fifo {
    return ( shift->[2] & $S_IFMT ) == $S_IFIFO;
}

1;
