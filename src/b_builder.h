#ifndef _B_BUILDER_H
#define _B_BUILDER_H

#include <sys/types.h>
#include "b_stack.h"
#include "b_string.h"
#include "b_header.h"
#include "b_buffer.h"
#include "b_error.h"

#define B_LOOKUP_SERVICE(s) ((b_lookup_service)s)

typedef int (*b_lookup_service)(void *ctx, uid_t uid, gid_t gid, b_string **user, b_string **group);

typedef struct _b_builder {
    b_buffer *             buf;
    b_error *              err;
    size_t                 total;
    struct lafe_matching * match;
    b_lookup_service       lookup_service;
    void *                 lookup_ctx;
    void *                 data;
} b_builder;

b_builder * b_builder_new(size_t block_factor);
b_error *   b_builder_get_error(b_builder *builder);
b_buffer *  b_builder_get_buffer(b_builder *builder);
void        b_builder_set_data(b_builder *builder, void *data);
void        b_builder_set_lookup_service(b_builder *builder, b_lookup_service service, void *ctx);
int         b_builder_is_excluded(b_builder *builder, const char *path);
int         b_builder_include(b_builder *builder, const char *pattern);
int         b_builder_include_from_file(b_builder *builder, const char *file);
int         b_builder_exclude(b_builder *builder, const char *pattern);
int         b_builder_exclude_from_file(b_builder *builder, const char *file);
int         b_builder_write_file(b_builder *builder, b_string *path, b_string *member_name, struct stat *st);
void        b_builder_destroy(b_builder *builder);

#endif /* _B_BUILDER_H */
