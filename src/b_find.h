#ifndef _B_FIND_H
#define _B_FIND_H

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include "b_builder.h"
#include "b_string.h"

#define B_FIND_FOLLOW_SYMLINKS (1 << 0)
#define B_FIND_CALLBACK(c)     ((b_find_callback)c)

typedef int (*b_find_callback)(b_builder_context *ctx, b_string *item, struct stat *st);

int b_find(b_string *path, b_find_callback callback, int flags, b_builder_context *ctx);

#endif /* _B_FIND_H */
