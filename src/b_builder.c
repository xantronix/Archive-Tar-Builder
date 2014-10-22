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
#include "b_buffer.h"
#include "b_builder.h"

b_builder *b_builder_new(size_t block_factor) {
    b_builder *builder;

    if ((builder = malloc(sizeof(*builder))) == NULL) {
        goto error_malloc;
    }

    if ((builder->buf = b_buffer_new(block_factor? block_factor: B_BUFFER_DEFAULT_FACTOR)) == NULL) {
        goto error_buffer_new;
    }

    if ((builder->err = b_error_new()) == NULL) {
        goto error_error_new;
    }

    builder->total          = 0;
    builder->match          = NULL;
    builder->options        = B_BUILDER_NONE;
    builder->lookup_service = NULL;
    builder->lookup_ctx     = NULL;
    builder->data           = NULL;

    return builder;

error_error_new:
    b_buffer_destroy(builder->buf);

error_buffer_new:
    free(builder);

error_malloc:
    return NULL;
}

enum b_builder_options b_builder_get_options(b_builder *builder) {
    if (builder == NULL) return B_BUILDER_NONE;

    return builder->options;
}

void b_builder_set_options(b_builder *builder, enum b_builder_options options) {
    builder->options = options;
}

b_error *b_builder_get_error(b_builder *builder) {
    if (builder == NULL) return NULL;

    return builder->err;
}

b_buffer *b_builder_get_buffer(b_builder *builder) {
    if (builder == NULL) return NULL;

    return builder->buf;
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

int b_builder_write_file(b_builder *builder, b_string *path, b_string *member_name, struct stat *st) {
    b_buffer *buf = builder->buf;
    b_error *err  = builder->err;

    int file_fd = 0;

    off_t wrlen = 0;

    b_header *header;
    b_header_block *block;

    if (buf == NULL) {
        errno = EINVAL;
        return -1;
    }

    if (err) {
        b_error_clear(err);
    }

    if ((st->st_mode & S_IFMT) == S_IFREG) {
        if ((file_fd = open(path->str, O_RDONLY)) < 0) {
            if (err) {
                b_error_set(err, B_ERROR_WARN, errno, "Cannot open file", path);
            }

            goto error_open;
        }
    }

    if ((header = b_header_for_file(path, member_name, st)) == NULL) {
        if (err) {
            b_error_set(err, B_ERROR_FATAL, errno, "Cannot build header for file", path);
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
            if (err) {
                b_error_set(err, B_ERROR_WARN, errno, "Cannot lookup user and group for file", path);
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

        /*
         * GNU extensions must be explicitly enabled to encode GNU LongLink
         * headers.
         */
        if (!(builder->options & B_BUILDER_GNU_EXTENSIONS)) {
            if (err) {
                errno = ENAMETOOLONG;

                b_error_set(err, B_ERROR_WARN, errno, "File name too long", member_name);
            }

            goto error_path_toolong;
        }

        if ((block = b_buffer_get_block(buf, B_HEADER_SIZE, &wrlen)) == NULL) {
            goto error_get_header_block;
        }

        if ((longlink_path = b_string_dup(member_name)) == NULL) {
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

        builder->total += wrlen;

        if ((wrlen = b_file_write_path_blocks(buf, longlink_path)) < 0) {
            if (err) {
                b_error_set(err, B_ERROR_FATAL, errno, "Cannot write long filename header", member_name);
            }

            goto error_write;
        }

        builder->total += wrlen;
    }

    /*
     * Then, of course, encode and write the real file header block.
     */
    if ((block = b_buffer_get_block(buf, B_HEADER_SIZE, &wrlen)) == NULL) {
        goto error_write;
    }

    if (b_header_encode_block(block, header) == NULL) {
        goto error_header_encode;
    }

    builder->total += wrlen;

    /*
     * Finally, end by writing the file contents.
     */
    if (file_fd) {
        if ((wrlen = b_file_write_contents(buf, file_fd, header->size)) < 0) {
            if (err) {
                b_error_set(err, B_ERROR_WARN, errno, "Cannot write file to archive", path);
            }

            goto error_write;
        }

        builder->total += wrlen;

        close(file_fd);

        file_fd = 0;
    }

    b_header_destroy(header);

    return 1;

error_write:
error_longlink_path_append:
error_longlink_path_dup:
error_get_header_block:
error_path_toolong:
error_header_encode:
error_lookup:
    b_header_destroy(header);

error_header_for_file:
    if (file_fd) {
        close(file_fd);
    }

error_open:
    return -1;
}

void b_builder_destroy(b_builder *builder) {
    if (builder == NULL) return;

    if (builder->buf) {
        b_buffer_destroy(builder->buf);
        builder->buf = NULL;
    }

    if (builder->err) {
        b_error_destroy(builder->err);
        builder->err = NULL;
    }

    builder->options = B_BUILDER_NONE;
    builder->total   = 0;
    builder->data    = NULL;

    lafe_cleanup_exclusions(&builder->match);

    builder->match = NULL;

    free(builder);
}
