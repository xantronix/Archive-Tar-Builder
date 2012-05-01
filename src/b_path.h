#ifndef _B_PATH_H
#define _B_PATH_H

#include "b_string.h"
#include "b_stack.h"

extern b_stack  * b_path_new(b_string *string);
extern b_string * b_path_clean(b_string *string);
extern b_string * b_path_clean_str(char *str);

#endif /* _B_PATH_H */
