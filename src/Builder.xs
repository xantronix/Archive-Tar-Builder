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

#include <sys/types.h>
#include <errno.h>
#include "b_string.h"
#include "b_find.h"
#include "b_builder.h"

typedef b_builder * Archive__Tar__Builder;

static int builder_lookup(SV *cache, uid_t uid, gid_t gid, b_string **user, b_string **group) {
    dSP;
    I32 i, retc;

    ENTER;
    SAVETMPS;

    /*
     * Prepare the stack for $cache->getpwuid()
     */
    PUSHMARK(SP);
    XPUSHs(cache);
    XPUSHs(sv_2mortal(newSViv(uid)));
    XPUSHs(sv_2mortal(newSViv(gid)));
    PUTBACK;

    if ((retc = call_method("lookup", G_ARRAY)) < 2) {
        goto error_lookup;
    }

    SPAGAIN;

    if (retc == 2) {
        size_t len = 0;
        SV *item;
        char *tmp;

        if ((item = POPs) != NULL && SvOK(item)) {
            tmp = SvPV(item, len);

            if ((*group = b_string_new_len(tmp, len)) == NULL) {
                goto error_string_new_group;
            }
        }

        if ((item = POPs) != NULL && SvOK(item)) {
            tmp = SvPV(item, len);

            if ((*user = b_string_new_len(tmp, len)) == NULL) {
                goto error_string_new_user;
            }
        }
    }

    PUTBACK;

    FREETMPS;
    LEAVE;

    return 0;

error_string_new_user:
    b_string_free(*group);

error_string_new_group:

error_lookup:
    PUTBACK;

    FREETMPS;
    LEAVE;

    return -1;
}

MODULE = Archive::Tar::Builder PACKAGE = Archive::Tar::Builder PREFIX = builder_

Archive::Tar::Builder
builder_new(klass)
    char *klass

    CODE:
        b_builder *builder;
        SV *cache = NULL;
        I32 i, retc;

        if ((builder = b_builder_new()) == NULL) {
            croak("%s: %s", "b_builder_new()", strerror(errno));
        }

        /*
         * Call Archive::Tar::Builder::UserCache->new()
         */
        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSVpvf("Archive::Tar::Builder::UserCache")));
        PUTBACK;

        if ((retc = call_method("new", G_SCALAR)) >= 1) {
            cache = POPs;
            SvREFCNT_inc(cache);
        }

        PUTBACK;

        b_builder_set_lookup_service(builder, B_LOOKUP_SERVICE(builder_lookup), cache); 

        RETVAL = builder;

    OUTPUT:
        RETVAL

void
builder_DESTROY(builder)
    Archive::Tar::Builder builder

    CODE:
        if (builder->lookup_ctx != NULL) {
            SvREFCNT_dec(builder->lookup_ctx);
        }

        b_builder_destroy(builder);

void
builder_add_as(builder, ...)
    Archive::Tar::Builder builder

    CODE:
        I32 i;

        if ((items - 1) % 2 != 0) {
            croak("Uneven number of arguments passed; must be in 'path' => 'member_name' format");
        }

        for (i=1; i<items; i+=2) {
            char *path        = SvPV_nolen(ST(i));
            char *member_name = SvPV_nolen(ST(i+1));

            if (b_builder_add_member_as(builder, path, member_name) < 0) {
                croak("%s: %s => %s: %s", "b_builder_add_member_as()", path, member_name, strerror(errno));
            }
        }

void
builder_add(builder, ...)
    Archive::Tar::Builder builder

    CODE:
        I32 i;

        for (i=1; i<items; i++) {
            char *path = SvPV_nolen(ST(i));

            if (b_builder_add_member(builder, path) < 0) {
                croak("%s: %s: %s", "b_builder_add_member()", path, strerror(errno));
            }
        }

int
builder_is_excluded(builder, path)
    Archive::Tar::Builder builder
    const char *path

    CODE:
        RETVAL = b_builder_is_excluded(builder, path);

    OUTPUT:
        RETVAL

void
builder_include(builder, pattern)
    Archive::Tar::Builder builder
    const char *pattern

    CODE:
        if (b_builder_include(builder, pattern) < 0) {
            croak("Cananot add inclusion pattern '%s' to list of inclusions: %s", pattern, strerror(errno));
        }

void
builder_include_from_file(builder, file)
    Archive::Tar::Builder builder
    const char *file

    CODE:
        if (b_builder_include_from_file(builder, file) < 0) {
            croak("Cannot add items to inclusion list from file %s: %s", file, strerror(errno));
        }

void
builder_exclude(builder, pattern)
    Archive::Tar::Builder builder
    const char *pattern

    CODE:
        if (b_builder_exclude(builder, pattern) < 0) {
            croak("Cannot add exclusion pattern '%s' to list of exclusions: %s", pattern, strerror(errno));
        }

void
builder_exclude_from_file(builder, file)
    Archive::Tar::Builder builder
    const char *file

    CODE:
        if (b_builder_exclude_from_file(builder, file) < 0) {
            croak("Cannot add items to exclusion list from file %s: %s", file, strerror(errno));
        }

size_t
builder_write(builder, fh)
    Archive::Tar::Builder builder
    PerlIO *fh

    ALIAS:
        Archive::Tar::Builder::start = 1

    CODE:
        size_t i, count;

        b_builder_context ctx = {
            .builder = builder,
            .fd      = PerlIO_fileno(fh),
            .path    = NULL,
            .total   = 0
        };

        count = b_stack_count(builder->members);

        for (i=0; i<count; i++) {
            b_builder_member *member;

            if ((member = b_stack_item_at(builder->members, i)) == NULL) {
                croak("%s: %s", "b_stack_item_at()", strerror(errno));
            }

            ctx.member = member;
            ctx.path   = member->path;

            if (b_find(member->path, B_FIND_CALLBACK(b_builder_write_file), 0, &ctx) < 0) {
                croak("%s: %s: %s", "b_find()", (ctx.path)->str, strerror(errno));
            }
        }

        RETVAL = ctx.total;

    OUTPUT:
        RETVAL
