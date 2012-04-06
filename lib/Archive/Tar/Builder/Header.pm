# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

package Archive::Tar::Builder::Header;

use strict;
use warnings;

use Archive::Tar::Builder::Bits;

use Math::BigInt ();
use Digest::SHA1 ();

our $BLOCK_SIZE     = 512;
our $MAX_USTAR_SIZE = 8589934591;

my %TYPES = (
    0 => $S_IFREG,
    2 => $S_IFLNK,
    3 => $S_IFCHR,
    4 => $S_IFBLK,
    5 => $S_IFDIR,
    6 => $S_IFIFO
);

sub inode_linktype {
    my ($st) = @_;

    foreach ( keys %TYPES ) {
        return $_ if ( $st->[2] & $S_IFMT ) == $TYPES{$_};
    }

    return 0;
}

sub for_file {
    my ( $class, %args ) = @_;

    my $file        = $args{'file'};
    my $member_name = $args{'member_name'};
    my $st          = $args{'st'};

    my @parts = split /\//, $member_name;

    if ( $st->dir && $member_name !~ /\/$/ ) {
        $member_name .= '/';
    }

    my $name_components = split_name_components( $st, @parts );
    my $size = $st->file ? $st->[7] : 0;

    my $major = 0;
    my $minor = 0;

    #
    # TODO: Add support for character and block devices
    #
    #if ( $st->[2] & ( $S_IFCHR | $S_IFBLK ) ) {
    #    $major = $inode->major;
    #    $minor = $inode->minor;
    #}

    return bless {
        'name'      => $member_name,
        'prefix'    => $name_components->{'prefix'},
        'suffix'    => $name_components->{'suffix'},
        'truncated' => $name_components->{'truncated'},
        'mode'      => $st->[2],
        'uid'       => $st->[4],
        'gid'       => $st->[5],
        'size'      => $size,
        'mtime'     => $st->[9],
        'linktype'  => inode_linktype($st),
        'linkdest'  => $st->link ? readlink($file) : '',
        'user'      => $args{'user'} ? $args{'user'} : '',
        'group'     => $args{'group'} ? $args{'group'} : '',
        'major'     => $major,
        'minor'     => $minor
    }, $class;
}

sub encode {
    my ( $self, %opts ) = @_;
    my $block = "\x00" x $BLOCK_SIZE;

    write_str( $block, 0, 100, $self->{'suffix'} );
    write_oct( $block, 100, 8, $self->{'mode'} & $S_IPERM, 7 );
    write_oct( $block, 108, 8, $self->{'uid'},             7 );
    write_oct( $block, 116, 8, $self->{'gid'},             7 );

    if ( $self->{'size'} > $MAX_USTAR_SIZE ) {
        unless ( $opts{'gnu_extensions'} ) {
            die('Cannot archive files >8GB; please use GNU extensions to overcome this limitation');
        }

        substr( $block, 124, 12, encode_base256_size( $self->{'size'} ) );
    }
    else {
        write_oct( $block, 124, 12, $self->{'size'}, 11 );
    }

    write_oct( $block, 136, 12, $self->{'mtime'}, 11 );
    write_str( $block, 148, 8, '        ' );

    if ( $self->{'linktype'} =~ /^[0-9]$/ ) {
        write_oct( $block, 156, 1, $self->{'linktype'}, 1 );
    }
    else {
        write_str( $block, 156, 1, $self->{'linktype'} );
    }

    write_str( $block, 157, 100, $self->{'linkdest'} );
    write_str( $block, 257, 6,   'ustar' );
    write_str( $block, 263, 2,   '00' );
    write_str( $block, 265, 32,  $self->{'user'} );
    write_str( $block, 297, 32,  $self->{'group'} );
    write_oct( $block, 329, 8, $self->{'major'}, 7 );
    write_oct( $block, 337, 8, $self->{'minor'}, 7 );
    write_str( $block, 345, 155, $self->{'prefix'} );

    my $checksum = checksum($block);

    write_oct( $block, 148, 8, $checksum, 7 );

    return $block;
}

sub encode_gnu {
    my ($self) = @_;

    return $self->encode( 'gnu_extensions' => 1 ) unless $self->{'truncated'};

    my $namelen = length $self->{'name'};

    my $longlink_header = bless {
        'prefix'   => '',
        'suffix'   => '././@LongLink',
        'mode'     => 0,
        'uid'      => 0,
        'gid'      => 0,
        'size'     => $namelen,
        'mtime'    => 0,
        'linktype' => 'L',
        'linkdest' => '',
        'user'     => '',
        'group'    => '',
        'major'    => 0,
        'minor'    => 0
      },
      ref $self;

    my $name_blocks = "\x00" x ( $namelen + $BLOCK_SIZE - ( $namelen % $BLOCK_SIZE ) );
    substr( $name_blocks, 0, $namelen ) = $self->{'name'};

    return $longlink_header->encode . $name_blocks . $self->encode( 'gnu_extensions' => 1 );
}

sub split_name_components {
    my ( $st, @parts ) = @_;

    my $truncated = 0;

    $parts[-1] .= '/' if $st->dir;

    my $got = 0;
    my ( @prefix_items, @suffix_items );

    while (@parts) {
        my $item = pop @parts;
        my $len  = length $item;

        #
        # If the first item found is greater than 100 characters in length,
        # truncate it so that it may fit in the standard tar name header field.
        # The first 7 characters of the SHA1 sum of the entire name will be
        # affixed to the end of this name suffix.
        #
        if ( $got == 0 && $len > 100 ) {
            my $truncated_len = $st->dir ? 92 : 93;
            my $full = join '/', @parts;

            $item = substr( $item, 0, $truncated_len ) . substr( Digest::SHA1::sha1_hex($full), 0, 7 );
            $item .= '/' if $st->dir;

            $len       = 100;
            $truncated = 1;
        }

        $got++ if $got;
        $got += $len;

        if ( $got <= 100 ) {
            push @suffix_items, $item;
        }
        else {
            push @prefix_items, $item;
        }
    }

    my $prefix = join( '/', reverse @prefix_items );
    my $suffix = join( '/', reverse @suffix_items );

    #
    # After arranging the prefix and suffix name components into the best slots
    # possible, now would be a good time to create a unique prefix value with
    # another short SHA1 sum string, in case the name prefix or suffix overflows
    # 155 characters.  This time the SHA1 sum is based on the prefix component
    # of the name, so as to avoid the pitfalls of a different suffix causing the
    # SHA1 sum in the prefix to differ given the same prefix, which would cause
    # tons of confusion, indeed.
    #
    if ( length($prefix) > 155 ) {
        $prefix = substr( $prefix, 0, 148 ) . substr( Digest::SHA1::sha1_hex($prefix), 0, 7 );
        $truncated = 1;
    }

    return {
        'prefix'    => $prefix,
        'suffix'    => $suffix,
        'truncated' => $truncated
    };
}

sub write_str {
    my ( $block, $offset, $len, $string ) = @_;

    if ( length($string) == $len ) {
        substr( $_[0], $offset, $len ) = $string;
    }
    else {
        substr( $_[0], $offset, $len ) = pack( "Z$len", $string );
    }

    return;
}

sub write_oct {
    my ( $block, $offset, $len, $value, $digits ) = @_;
    my $string     = sprintf( "%.${digits}o", $value );
    my $sub_offset = length($string) - $digits;
    my $substring  = substr( $string, $sub_offset, $digits );

    if ( $len == $digits ) {
        substr( $_[0], $offset, $len ) = $substring;
    }
    else {
        substr( $_[0], $offset, $len ) = pack( "Z$len", $substring );
    }

    return;
}

sub encode_base256_size {
    my $size = Math::BigInt->new(shift);
    my $ret = "\x80" . ( "\x0" x 11 );
    my @bytes;

    until ( $size->is_zero() ) {
        push @bytes, $size->copy->band(0xff);
        $size->brsft(8);
    }

    my $len = scalar @bytes;

    substr( $ret, 12 - $len, $len ) = pack( 'C*', reverse @bytes );

    return $ret;
}

sub checksum {
    my ($block) = @_;
    my $sum = 0;

    foreach ( unpack 'C*', $block ) {
        $sum += $_;
    }

    return $sum;
}

sub file {
    my ($self) = @_;

    return $TYPES{ $self->{'linktype'} } == $S_IFREG;
}

sub link {
    my ($self) = @_;

    return $self->{'linktype'} == 1;
}

sub symlink {
    my ($self) = @_;

    return $TYPES{ $self->{'linktype'} } == $S_IFLNK;
}

sub char {
    my ($self) = @_;

    return $TYPES{ $self->{'linktype'} } == $S_IFCHR;
}

sub block {
    my ($self) = @_;

    return $TYPES{ $self->{'linktype'} } == $S_IFBLK;
}

sub dir {
    my ($self) = @_;

    return $TYPES{ $self->{'linktype'} } == $S_IFDIR;
}

sub fifo {
    my ($self) = @_;

    return $TYPES{ $self->{'linktype'} } == $S_IFIFO;
}

sub contig {
    my ($self) = @_;

    return $self->{'linktype'} == 7;
}

1;
