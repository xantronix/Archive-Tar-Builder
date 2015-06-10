#ifdef __linux__
#define _GNU_SOURCE         /* See feature_test_macros(7) */
#endif
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

off_t b_file_write_contents(b_buffer *buf, int file_fd, off_t file_size) {
    ssize_t rlen = 0, blocklen = 0;
    off_t total = 0, real_total = 0, max_read = 0;
#ifdef __linux__
    int emptied_buffer = 0, splice_total = 0;
#endif

    do {
        if (b_buffer_full(buf)) {
            if (b_buffer_flush(buf) < 0) {
                goto error_io;
            }
            emptied_buffer = 1;
        }

        max_read = file_size - real_total;

        if (max_read == 0) { break; }
#ifdef __linux__
        /* Once we have cleared out the buffer we can
           read the rest of the file with splice and
           write out a tar padding */
        if ( emptied_buffer && buf->is_pipe ) {
            if ( rlen = splice(file_fd, NULL, buf->fd, NULL, max_read, 0) ){
                if (rlen < 0) {
                    goto splice_error_io;
                }
                splice_total += rlen;
                total        += rlen;
            }
        } else {
#endif
            unsigned char *block;

            if ((block = b_buffer_get_block(buf, b_buffer_unused(buf), &blocklen)) == NULL) {
                goto error_io;
            }

            if (max_read > blocklen) max_read = blocklen;


           read_retry:
            if ((rlen = read(file_fd, block, max_read)) < max_read) {
                if (errno == EINTR) { goto read_retry; }

                goto error_io;
            }

            total      += blocklen;
            /*
             * Reclaim any amount of bytes from the buffer that weren't used to
             * store the chunk read() from the filesystem.
             */
            if (blocklen - rlen) {
                total -= b_buffer_reclaim(buf, rlen, blocklen);
            }
#ifdef __linux__
        }
#endif
        real_total += rlen;
    } while (rlen > 0);

#ifdef __linux__
    if (splice_total && splice_total % B_BUFFER_BLOCK_SIZE != 0) {
        // finished splice, now complete the block
        // by writing out zeros to make tar happy
        if ( (write(buf->fd, buf->data, B_BUFFER_BLOCK_SIZE - (splice_total % B_BUFFER_BLOCK_SIZE)))<0) {
            goto error_io;
        }
    }
#endif

    return total;

error_io:
    if (!errno) { errno = EINVAL; }
    return -1;

#ifdef __linux__
splice_error_io:
    if (splice_total && splice_total % B_BUFFER_BLOCK_SIZE != 0) {
        int saved_errno = errno;
         // finished splice, now complete the block
        // by writing out zeros to make tar happy
        if ( (write(buf->fd, buf->data, B_BUFFER_BLOCK_SIZE - (splice_total % B_BUFFER_BLOCK_SIZE)))<0) {
            // We want to return the error
            // from splice as it was the first error
            // we encountered
            errno = saved_errno;
        }
    }
    return -1;
#endif


}
