#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include "match_engine.h"
#include "b_file.h"
#include "b_path.h"
#include "b_string.h"
#include "b_header.h"
#include "b_stack.h"
#include "b_builder.h"

static b_builder_member *b_builder_member_new(char *path, char *member_name) {
    b_builder_member *member;

    if ((member = malloc(sizeof(*member))) == NULL) {
        goto error_malloc;
    }

    if ((member->path = b_path_clean_str(path)) == NULL) {
        goto error_path_clean;
    }

    if ((member->member_name = b_path_clean_str(member_name)) == NULL) {
        goto error_path_clean_member_name;
    }

    /*
     * It is quite important to compare the finished, cleaned variants of the given
     * path and intended member name, as any differences in formatting provided by
     * the user that otherwise have no semantic meaning may yield identically cleaned
     * paths.
     */
    member->has_different_name = strcmp(member->path->str, member->member_name->str)? 1: 0;

    return member;

error_path_clean_member_name:
    b_string_free(member->path);

error_path_clean:
    free(member);

error_malloc:
    return NULL;
}

static void b_builder_member_destroy(b_builder_member *member) {
    b_string_free(member->path);
    b_string_free(member->member_name);

    member->path        = NULL;
    member->member_name = NULL;

    free(member);
}

b_builder *b_builder_new() {
    b_builder *builder;

    if ((builder = malloc(sizeof(*builder))) == NULL) {
        goto error_malloc;
    }

    if ((builder->members = b_stack_new(0)) == NULL) {
        goto error_stack_new;
    }

    b_stack_set_destructor(builder->members, B_STACK_DESTRUCTOR(b_builder_member_destroy));

    builder->match          = NULL;
    builder->lookup_service = NULL;
    builder->lookup_ctx     = NULL;
    builder->data           = NULL;

    return builder;

error_stack_new:
    free(builder);

error_malloc:
    return NULL;
}

void b_builder_set_data(b_builder *builder, void *data) {
    if (builder == NULL) return;

    builder->data = data;
}

/*
 * The caller should assume responsibility for initializing and destroying the
 * user lookup service as appropriate.
 */
void b_builder_set_lookup_service(b_builder *builder, b_lookup_service service, void *ctx) {
    builder->lookup_service = service;
    builder->lookup_ctx     = ctx;
}

int b_builder_add_member_as(b_builder *builder, char *path, char *member_name) {
    b_builder_member *member;

    if ((member = b_builder_member_new(path, member_name)) == NULL) {
        goto error_member_new;
    }

    if (b_stack_push(builder->members, member) == NULL) {
        goto error_stack_push;
    }

    return 0;

error_stack_push:
    b_builder_member_destroy(member);

error_member_new:
    return -1;
}

int b_builder_add_member(b_builder *builder, char *path) {
    return b_builder_add_member_as(builder, path, path);
}

int b_builder_is_excluded(b_builder *builder, const char *path) {
    return lafe_excluded(builder->match, path);
}

int b_builder_include(b_builder *builder, const char *pattern) {
    return lafe_include(&builder->match, pattern);
}

int b_builder_include_from_file(b_builder *builder, const char *file) {
    return lafe_include_from_file(&builder->match, file, 0);
}

int b_builder_exclude(b_builder *builder, const char *pattern) {
    return lafe_exclude(&builder->match, pattern);
}

int b_builder_exclude_from_file(b_builder *builder, const char *file) {
    return lafe_exclude_from_file(&builder->match, file);
}

void b_builder_destroy(b_builder *builder) {
    b_stack_destroy(builder->members);
    lafe_cleanup_exclusions(&builder->match);

    builder->members = NULL;
    builder->match   = NULL;
    builder->data    = NULL;

    free(builder);
}

int b_builder_write_file(b_builder_context *ctx, b_string *path, struct stat *st) {
    b_builder *builder       = ctx->builder;
    b_header_block *block    = &ctx->block;
    b_builder_member *member = ctx->member;
    int fd                   = ctx->fd;

    int file_fd = 0;

    b_string *new_member_name = NULL;

    ssize_t wrlen = 0;

    b_header *header;

    ctx->path = path;

    if (ctx->err) {
        b_error_clear(ctx->err);
    }

    if (member->has_different_name) {
        if ((new_member_name = b_string_dup(member->member_name)) == NULL) {
            goto error_string_dup_member_name;
        }

        if (b_string_append_str(new_member_name, path->str + b_string_len(member->path)) == NULL) {
            goto error_string_append_path;
        }
    }

    /*
     * Only test to see if the current member is excluded if any exclusions or
     * inclusions were actually specified, to save time calling the exclusion
     * engine.
     */
    if (builder->match != NULL && lafe_excluded(builder->match, (const char *)path->str)) {
        return 0;
    }

    if ((st->st_mode & S_IFMT) == S_IFREG) {
        if ((file_fd = open(path->str, O_RDONLY)) < 0) {
            if (ctx->err) {
                b_error_set(ctx->err, B_ERROR_WARN, errno, "Cannot open file", path);
            }

            goto error_open;
        }
    }

    if ((header = b_header_for_file(path, new_member_name? new_member_name: path, st)) == NULL) {
        if (ctx->err) {
            b_error_set(ctx->err, B_ERROR_FATAL, errno, "Cannot build header for file", path);
        }

        goto error_header_for_file;
    }

    /*
     * If there is a user lookup service installed, then resolve the user and
     * group of the current filesystem object and supply them within the
     * b_header object.
     */
    if (builder->lookup_service != NULL) {
        b_string *user = NULL, *group = NULL;

        if (builder->lookup_service(builder->lookup_ctx, st->st_uid, st->st_gid, &user, &group) < 0) {
            if (ctx->err) {
                b_error_set(ctx->err, B_ERROR_WARN, errno, "Cannot lookup user and group for file", path);
            }

            goto error_lookup;
        }

        if (b_header_set_usernames(header, user, group) < 0) {
            goto error_lookup;
        }
    }

    /*
     * If the header is marked to contain truncated paths, then write a GNU
     * longlink header, followed by the blocks containing the path name to be
     * assigned.
     */
    if (header->truncated) {
        b_string *longlink_path;

        if ((longlink_path = b_string_dup(path)) == NULL) {
            goto error_longlink_path_dup;
        }

        if ((st->st_mode & S_IFMT) == S_IFDIR) {
            if ((b_string_append_str(longlink_path, "/")) == NULL) {
                goto error_longlink_path_append;
            }
        }

        if (b_header_encode_longlink_block(block, longlink_path) == NULL) {
            goto error_header_encode;
        }

        if ((wrlen = write(fd, block, sizeof(*block))) < 0) {
            if (ctx->err) {
                b_error_set(ctx->err, B_ERROR_FATAL, errno, "Cannot write file header", path);
            }

            goto error_write;
        }

        ctx->total += wrlen;

        if ((wrlen = b_file_write_path_blocks(fd, longlink_path)) < 0) {
            if (ctx->err) {
                b_error_set(ctx->err, B_ERROR_FATAL, errno, "Cannot write long filename header", path);
            }

            goto error_write;
        }

        ctx->total += wrlen;
    }

    /*
     * Then, of course, encode and write the real file header block.
     */
    if (b_header_encode_block(block, header) == NULL) {
        goto error_header_encode;
    }

    if ((wrlen = write(fd, block, sizeof(*block))) < 0) {
        goto error_write;
    }

    ctx->total += wrlen;

    /*
     * Finally, end by writing the file contents.
     */
    if (file_fd) {
        if ((wrlen = b_file_write_contents(fd, file_fd)) < 0) {
            if (ctx->err) {
                b_error_set(ctx->err, B_ERROR_WARN, errno, "Cannot write file to archive", path);
            }

            goto error_write;
        }

        ctx->total += wrlen;

        close(file_fd);

        file_fd = 0;
    }

    if (new_member_name != NULL) {
        b_string_free(new_member_name);
    }

    b_header_destroy(header);

    return 1;

error_write:
error_longlink_path_append:
error_longlink_path_dup:
error_header_encode:
error_lookup:
    b_header_destroy(header);

error_header_for_file:
    if (file_fd) {
        close(file_fd);
    }

error_open:
error_string_append_path:
    if (new_member_name != NULL) {
        b_string_free(new_member_name);
    }

error_string_dup_member_name:
    return -1;
}
