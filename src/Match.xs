/*
 * Copyright (c) 2012, cPanel, Inc.
 * All rights reserved.
 * http://cpanel.net/
 *
 * This is free software; you can redistribute it and/or modify it under the
 * same terms as Perl itself.  See the Perl manual section 'perlartistic' for
 * further information.
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <errno.h>
#include "matching.h"

typedef struct match_data {
    struct lafe_matching *data;
} * Archive__Tar__Builder__Match;

MODULE = Archive::Tar::Builder PACKAGE = Archive::Tar::Builder::Match PREFIX = match_

Archive::Tar::Builder::Match
match_new(klass)
    char *klass

    CODE:
        struct match_data *ret;

        if ((ret = malloc(sizeof(*ret))) == NULL) {
            croak("%s: %s", "malloc()", strerror(errno));
        }

        ret->data = NULL;

        RETVAL = ret;
    OUTPUT:
        RETVAL

void
match_DESTROY(match)
    Archive::Tar::Builder::Match match

    CODE:
        lafe_cleanup_exclusions(&match->data);
        free(match);

void
match_include(match, pattern)
    Archive::Tar::Builder::Match match
    const char *pattern

    CODE:
        if (lafe_include(&match->data, pattern) < 0) {
            croak("Cannot add pattern to inclusion list: %s", strerror(errno));
        }

void
match_exclude(match, pattern)
    Archive::Tar::Builder::Match match
    const char *pattern

    CODE:
        if (lafe_exclude(&match->data, pattern) < 0) {
            croak("Cannot add pattern to exclusion list: %s", strerror(errno));
        }

void
match_include_from_file(match, file)
    Archive::Tar::Builder::Match match
    const char *file

    CODE:
        if (lafe_include_from_file(&match->data, file, 0) < 0) {
            croak("Cannot add items to inclusion list from file %s: %s", file, strerror(errno));
        }

void
match_exclude_from_file(match, file)
    Archive::Tar::Builder::Match match
    const char *file

    CODE:
        if (lafe_exclude_from_file(&match->data, file) < 0) {
            croak("Cannot add items to exclusion list from file %s: %s", file, strerror(errno));
        }

int
match_is_excluded(match, path)
    Archive::Tar::Builder::Match match
    const char *path

    CODE:
        RETVAL = lafe_excluded(match->data, path);
    OUTPUT:
        RETVAL
