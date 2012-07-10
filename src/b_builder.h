#ifndef _B_BUILDER_H
#define _B_BUILDER_H

#define B_BLOCK_SIZE  512
#define B_BUFFER_SIZE B_BLOCK_SIZE

#include <sys/types.h>
#include "b_stack.h"
#include "b_string.h"
#include "b_header.h"

#define B_LOOKUP_SERVICE(s) ((b_lookup_service)s)

typedef int (*b_lookup_service)(void *ctx, uid_t uid, gid_t gid, b_string **user, b_string **group);

typedef struct _b_builder {
    b_stack *              members;
    struct lafe_matching * match;
    b_lookup_service       lookup_service;
    void *                 lookup_ctx;
} b_builder;

typedef struct _b_builder_member {
    b_string * path;
    b_string * member_name;
    int        has_different_name;
} b_builder_member;

typedef struct _b_builder_context {
    b_builder *        builder;
    b_builder_member * member;
    b_header_block     block;
    b_string *         path;
    int                fd;
    size_t             total;
} b_builder_context;

extern b_builder * b_builder_new();
extern void        b_builder_set_lookup_service(b_builder *builder, b_lookup_service service, void *ctx);
extern int         b_builder_add_member_as(b_builder *builder, char *path, char *member_name);
extern int         b_builder_add_member(b_builder *builder, char *path);
extern int         b_builder_is_excluded(b_builder *builder, const char *path);
extern int         b_builder_include(b_builder *builder, const char *pattern);
extern int         b_builder_include_from_file(b_builder *builder, const char *file);
extern int         b_builder_exclude(b_builder *builder, const char *pattern);
extern int         b_builder_exclude_from_file(b_builder *builder, const char *file);
extern int         b_builder_write_file(b_builder_context *ctx, b_string *path, struct stat *st);
extern void        b_builder_destroy(b_builder *builder);

#endif /* _B_BUILDER_H */
