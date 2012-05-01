#ifndef _B_FIND_H
#define _B_FIND_H

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include "b_string.h"

#define B_FIND_FOLLOW_SYMLINKS (1 << 0)
#define B_FIND_CALLBACK(c)     ((b_find_callback)c)

typedef int (*b_find_callback)(void *context, b_string *item, struct stat *st);

extern int b_find(b_string *path, b_find_callback callback, int flags, void *context);

#endif /* _B_FIND_H */
