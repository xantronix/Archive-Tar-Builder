#ifndef _B_FILE_H
#define _B_FILE_H

#define B_BLOCK_SIZE  512

#include <sys/types.h>
#include "b_string.h"
#include "b_buffer.h"

ssize_t b_file_write_contents(b_buffer *buf, int file_fd);
ssize_t b_file_write_path_blocks(b_buffer *buf, b_string *path);

#endif /* _B_FILE_H */
