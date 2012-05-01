#ifndef _B_UTIL_H
#define _B_UTIL_H

#include <sys/stat.h>
#include "b_string.h"
#include "b_stack.h"

extern b_string * b_string_join(char *sep, b_stack *items);
extern b_string * b_readlink(b_string *path, struct stat *st);

#endif /* _B_UTIL_H */
