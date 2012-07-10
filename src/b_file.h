#ifndef _B_FILE_H
#define _B_FILE_H

#define B_BLOCK_SIZE 512

#include <sys/types.h>
#include "b_string.h"

extern ssize_t b_file_write_contents(int tar_fd, b_string *path);
extern ssize_t b_file_write_path_blocks(int tar_fd, b_string *path);

#endif /* _B_FILE_H */
