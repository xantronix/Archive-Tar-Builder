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
#include "b_file.h"

/*
 * Meant to be used in conjunction with header.c/b_header_encode_longlink_block(),
 * this method will write out as many 512-byte blocks as necessary to contain the
 * full path.
 */
ssize_t b_file_write_path_blocks(int tar_fd, b_string *path) {
    size_t i, len;
    ssize_t wrlen = 0, total = 0;
    unsigned char *block;

    /*
     * I could allocate the entire thing on stack, but things could get
     * expensive rather quickly...
     */
    if ((block = malloc(B_BLOCK_SIZE)) == NULL) {
        goto error_malloc;
    }

    len = b_string_len(path);

    for (i=0; i<len; i+=B_BLOCK_SIZE) {
        size_t left = len - i;

        if (left < B_BLOCK_SIZE) {
            memset(block, 0x00, B_BLOCK_SIZE);
            memcpy(block, path->str + i, left);

            if ((wrlen = write(tar_fd, block, B_BLOCK_SIZE)) < 0) {
                goto error_io;
            }

            total += wrlen;
        } else {
            if ((wrlen = write(tar_fd, path->str + i, B_BLOCK_SIZE)) < 0) {
                goto error_io;
            }

            total += wrlen;
        }
    }

    free(block);

    return total;

error_io:
    free(block);

error_malloc:
    return -1;
}

ssize_t b_file_write_contents(int tar_fd, b_string *path) {
    int fd;
    int tmp_errno;

    unsigned char buf[B_BUFFER_SIZE];
    ssize_t rlen = 0, wrlen = 0, total = 0;

    if ((fd = open(path->str, O_RDONLY)) < 0) {
        goto error_open;
    }

    while ((rlen = read(fd, buf, B_BUFFER_SIZE)) > 0) {
        size_t padlen = B_BUFFER_SIZE - rlen;

        if (padlen > 0) {
            memset(buf + B_BUFFER_SIZE - padlen, 0x00, padlen);
        }

        if ((wrlen = write(tar_fd, buf, B_BUFFER_SIZE)) < 0) {
            goto error_io;
        }

        total += wrlen;
    }

    if (rlen < 0) {
        goto error_io;
    }

    if (close(fd) < 0) {
        goto error_close;
    }

    return total;

error_io:
    tmp_errno = errno;
    
    if (close(fd) < 0) {
        /* Restore previous errno in case of close() failure */
        errno = tmp_errno;
    }
       
error_close:
error_open:
    return -1;
}
