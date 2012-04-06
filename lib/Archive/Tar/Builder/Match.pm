# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

package Archive::Tar::Builder::Match;

use strict;
use warnings;

use Exporter ();
use XSLoader ();

BEGIN {
    use vars qw(@ISA $VERSION);

    our @ISA     = qw(Exporter);
    our $VERSION = '0.3';
}

XSLoader::load( 'Archive::Tar::Builder', $VERSION );

1;
