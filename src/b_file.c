#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>

#include "b_builder.h"
#include "b_header.h"
#include "b_string.h"
#include "b_buffer.h"
#include "b_file.h"

/*
 * Meant to be used in conjunction with header.c/b_header_encode_longlink_block(),
 * this method will write out as many 512-byte blocks as necessary to contain the
 * full path.
 */
off_t b_file_write_path_blocks(b_buffer *buf, b_string *path) {
    size_t i, len;
    ssize_t blocklen = 0;
    off_t total = 0;

    len = b_string_len(path);

    for (i=0; i<len; i+=B_BLOCK_SIZE) {
        size_t left    = len - i;
        size_t copylen = left < B_BLOCK_SIZE? left: B_BLOCK_SIZE;

        unsigned char *block;

        if ((block = b_buffer_get_block(buf, B_BLOCK_SIZE, &blocklen)) == NULL) {
            goto error_io;
        }

        memcpy(block, path->str + i, copylen);

        total += blocklen;
    }

    return total;

error_io:
    return -1;
}

off_t b_file_write_pax_path_blocks(b_buffer *buf, b_string *path) {
    size_t i, len, full_len, buflen;
    ssize_t blocklen = 0;
    off_t total = 0;
    char shortbuf[32];

    len = b_string_len(path);

    full_len = b_header_compute_pax_length(path);

    /* In case we have a broken snprintf. */
    if (full_len == (size_t)-1)
        goto error_io;

    buflen = snprintf(shortbuf, sizeof(shortbuf), "%d path=", full_len);

    for (i=0; i<full_len; i+=B_BLOCK_SIZE) {
        size_t offset  = i == 0 ? buflen : 0;
        size_t left    = full_len - i - offset;
        size_t copylen = left < B_BLOCK_SIZE? left: B_BLOCK_SIZE;

        unsigned char *block;

        if ((block = b_buffer_get_block(buf, B_BLOCK_SIZE, &blocklen)) == NULL) {
            goto error_io;
        }

        /* First block. */
        if (i == 0) {
            memcpy(block, shortbuf, buflen);
        }

        memcpy(block + offset, path->str + i, copylen);

        /* Last block. */
        if (i + B_BLOCK_SIZE >= full_len) {
            uint8_t *buf = block;
            buf[offset + copylen - 1] = '\n';
        }

        total += blocklen;
    }

    return total;

error_io:
    return -1;
}

off_t b_file_write_contents(b_buffer *buf, int file_fd, off_t file_size) {
    ssize_t rlen = 0, blocklen = 0;
    off_t total = 0, real_total = 0, max_read = 0;

    do {
        unsigned char *block;

        if (b_buffer_full(buf)) {
            if (b_buffer_flush(buf) < 0) {
                goto error_io;
            }
        }

        if ((block = b_buffer_get_block(buf, b_buffer_unused(buf), &blocklen)) == NULL) {
            goto error_io;
        }

        max_read = file_size - real_total;
        if (max_read > blocklen) max_read = blocklen;

        if ((rlen = read(file_fd, block, max_read)) < max_read) {
            errno = EINVAL;

            goto error_io;
        }

        total      += blocklen;
        real_total += rlen;

        /*
         * Reclaim any amount of bytes from the buffer that weren't used to
         * store the chunk read() from the filesystem.
         */
        if (blocklen - rlen) {
            total -= b_buffer_reclaim(buf, rlen, blocklen);
        }
    } while (rlen > 0);

    if (rlen < 0) {
        errno = EINVAL;

        goto error_io;
    }

    return total;

error_io:
    return -1;
}
