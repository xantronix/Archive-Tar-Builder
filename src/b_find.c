#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include "b_string.h"
#include "b_stack.h"
#include "b_path.h"
#include "b_find.h"

static inline int b_stat(b_string *path, struct stat *st, int flags) {
    int (*statfn)(const char *, struct stat *) = (flags & B_FIND_FOLLOW_SYMLINKS)? stat: lstat;

    return statfn(path->str, st);
}

typedef struct {
    DIR *      dp;
    b_string * path;
} b_dir;

b_dir *b_dir_open(b_string *path) {
    b_dir *dir;

    if ((dir = malloc(sizeof(*dir))) == NULL) {
        goto error_malloc;
    }

    if ((dir->dp = opendir(path->str)) == NULL) {
        goto error_opendir;
    }

    if ((dir->path = b_string_dup(path)) == NULL) {
        goto error_string_dup;
    }

    return dir;

error_string_dup:
    closedir(dir->dp);

error_opendir:
    free(dir);

error_malloc:
    return NULL;
}

static void b_dir_close(b_dir *item) {
    closedir(item->dp);
}

static void b_dir_destroy(b_dir *item) {
    b_dir_close(item);
    b_string_free(item->path);

    item->path = NULL;

    free(item);
}

typedef struct {
    struct stat * st;
    b_string *    path;
    b_string *    name;
} b_dir_item;

static b_dir_item *b_dir_read(b_dir *dir, int flags) {
    b_dir_item *item;
    struct dirent *entry;

    /*
     * If readdir() returns null, then don't bother with setting up any other
     * state.
     */
    if ((entry = readdir(dir->dp)) == NULL) {
        goto error_readdir;
    }

    if ((item = malloc(sizeof(*item))) == NULL) {
        goto error_malloc;
    }

    if ((item->st = malloc(sizeof(*item->st))) == NULL) {
        goto error_malloc_st;
    }

    if ((item->path = b_string_dup(dir->path)) == NULL) {
        goto error_string_dup;
    }

    if ((item->name = b_string_new(entry->d_name)) == NULL) {
        goto error_string_new;
    }

    /*
     * If the current path is /, then do not bother adding another slash.
     */
    if (strcmp(item->path->str, "/") != 0) {
        if (b_string_append_str(item->path, "/") == NULL) {
            goto error_string_append;
        }
    }

    if (b_string_append_str(item->path, entry->d_name) == NULL) {
        goto error_string_append;
    }

    if (b_stat(item->path, item->st, flags) < 0) {
        goto error_stat;
    }

    return item;

error_stat:
error_string_append:
    b_string_free(item->name);

error_string_new:
    b_string_free(item->path);

error_string_dup:
    free(item->st);

error_malloc_st:
    free(item);

error_malloc:
error_readdir:
    return NULL;
}

static void b_dir_item_free(b_dir_item *item) {
    b_string_free(item->name);
    b_string_free(item->path);

    free(item->st);

    item->name = NULL;
    item->path = NULL;
    item->st   = NULL;

    free(item);
}

/*
 * callback() should return a 0 or 1; 0 to indicate that traversal at the current
 * level should halt, or 1 that it should continue.
 */
int b_find(b_string *path, b_find_callback callback, int flags, void *context) {
    b_stack *dirs;
    struct stat st;
    b_dir *dir;
    int res;

    b_string *cleanpath;

    if ((cleanpath = b_path_clean(path)) == NULL) {
        goto error_path_clean;
    }

    if ((dirs = b_stack_new(0)) == NULL) {
        goto error_stack_new;
    }

    b_stack_set_destructor(dirs, B_STACK_DESTRUCTOR(b_dir_destroy));

    if (b_stat(cleanpath, &st, flags) < 0) {
        goto error_stat;
    }

    /*
     * If the item we're dealing with is not a directory, or is not wanted by the
     * callback, then do not bother with traversal code.  Otherwise, all code after
     * these guard clauses pertains to the case of 'path' being a directory.
     */
    res = callback(context, cleanpath, &st);

    if (res == 0) {
        goto cleanup;
    } else if (res < 0) {
        goto error_callback_top;
    }

    if ((st.st_mode & S_IFMT) != S_IFDIR) {
        return 0;
    }

    if ((dir = b_dir_open(cleanpath)) == NULL) {
        goto error_dir_open;
    }

    if (b_stack_push(dirs, dir) == NULL) {
        goto error_stack_push;
    }

    while ((dir = b_stack_pop(dirs)) != NULL) {
        b_dir_item *item;

        while ((item = b_dir_read(dir, flags)) != NULL) {
            if (strcmp(item->name->str, ".") == 0 || strcmp(item->name->str, "..") == 0) {
                goto cleanup_item;
            }

            res = callback(context, item->path, item->st);

            if (res == 0) {
                goto cleanup_item;
            } else if (res < 0) {
                goto error_item;
            }

            if ((item->st->st_mode & S_IFMT) == S_IFDIR) {
                b_dir *newdir;

                if ((newdir = b_dir_open(item->path)) == NULL) {
                    if (errno == EACCES) {
                        goto cleanup_item;
                    } else {
                        goto error_item;
                    }
                }

                if (b_stack_push(dirs, newdir) == NULL) {
                    b_dir_destroy(newdir);

                    goto error_stack_push;
                }
            }

cleanup_item:
            b_dir_item_free(item);

            continue;

error_item:
            b_dir_item_free(item);

            goto error_cleanup;
        }

        b_dir_destroy(dir);
    }

cleanup:
    b_stack_destroy(dirs);
    b_string_free(cleanpath);

    return 0;

error_cleanup:
error_stack_push:
    b_dir_destroy(dir);

error_dir_open:
error_callback_top:
error_stat:
    b_stack_destroy(dirs);

error_stack_new:
    b_string_free(cleanpath);

error_path_clean:
    return -1;
}
