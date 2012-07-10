#ifndef _B_STRING_H
#define _B_STRING_H

#include <sys/types.h>

typedef struct _b_string {
    char * str;
    size_t len;
} b_string;

extern b_string * b_string_new_len(char *str, size_t len);
extern b_string * b_string_new(char *str);
extern b_string * b_string_dup(b_string *string);
extern b_string * b_string_append(b_string *string, b_string *add);
extern b_string * b_string_append_str(b_string *string, char *add);
extern size_t     b_string_len(b_string *string);
extern void       b_string_free(b_string *string);

#endif /* _B_STRING_H */
