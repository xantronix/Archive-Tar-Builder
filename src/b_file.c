#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>

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

off_t b_file_write_contents(b_buffer *buf, int file_fd) {
    ssize_t rlen = 0, blocklen = 0;
    off_t total = 0;

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

        if ((rlen = read(file_fd, block, blocklen)) < 0) {
            goto error_io;
        }

        total += blocklen;

        /*
         * Reclaim any amount of bytes from the buffer that weren't used to
         * store the chunk read() from the filesystem.
         */
        if (blocklen - rlen) {
            total -= b_buffer_reclaim(buf, rlen, blocklen);
        }
    } while (rlen > 0);

    if (rlen < 0) {
        goto error_io;
    }

    return total;

error_io:
    return -1;
}
