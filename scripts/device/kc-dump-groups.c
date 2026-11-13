#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SQLITE_OK 0
#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_OPEN_READONLY 0x00000001
#define GROUP_BUFFER_LIMIT (1024 * 1024)

typedef int (*sqlite3_open_v2_fn)(const char *, void **, int, const char *);
typedef int (*sqlite3_close_fn)(void *);
typedef int (*sqlite3_prepare_v2_fn)(void *, const char *, int, void **, const char **);
typedef int (*sqlite3_step_fn)(void *);
typedef int (*sqlite3_finalize_fn)(void *);
typedef const unsigned char *(*sqlite3_column_text_fn)(void *, int);

typedef struct {
    void *handle;
    sqlite3_open_v2_fn open;
    sqlite3_close_fn close;
    sqlite3_prepare_v2_fn prepare;
    sqlite3_step_fn step;
    sqlite3_finalize_fn finalize;
    sqlite3_column_text_fn column_text;
} SQLiteAPI;

static int callback_unused(void) { return 0; }

int main(void) {
    SQLiteAPI api = {0};
    api.handle = dlopen("/usr/lib/libsqlite3.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (api.handle == NULL) return 1;
    api.open = (sqlite3_open_v2_fn)dlsym(api.handle, "sqlite3_open_v2");
    api.close = (sqlite3_close_fn)dlsym(api.handle, "sqlite3_close");
    api.prepare = (sqlite3_prepare_v2_fn)dlsym(api.handle, "sqlite3_prepare_v2");
    api.step = (sqlite3_step_fn)dlsym(api.handle, "sqlite3_step");
    api.finalize = (sqlite3_finalize_fn)dlsym(api.handle, "sqlite3_finalize");
    api.column_text = (sqlite3_column_text_fn)dlsym(api.handle, "sqlite3_column_text");
    if (!api.open || !api.close || !api.prepare || !api.step || !api.finalize || !api.column_text) return 1;

    void *db = NULL;
    if (api.open("/var/Keychains/keychain-2.db", &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) return 1;
    void *statement = NULL;
    const char *tail = NULL;
    if (api.prepare(db, "SELECT DISTINCT agrp FROM genp WHERE agrp IS NOT NULL ORDER BY agrp",
                    -1, &statement, &tail) != SQLITE_OK) {
        api.close(db);
        return 1;
    }
    size_t total = 0;
    int status = SQLITE_OK;
    while ((status = api.step(statement)) == SQLITE_ROW) {
        const unsigned char *group = api.column_text(statement, 0);
        if (group == NULL || group[0] == '\0') continue;
        size_t length = strlen((const char *)group);
        if (length > GROUP_BUFFER_LIMIT || total > GROUP_BUFFER_LIMIT - length - 1) {
            status = 1;
            break;
        }
        if (fwrite(group, 1, length, stdout) != length || fputc('\n', stdout) == EOF) {
            status = 1;
            break;
        }
        total += length + 1;
    }
    if (status == SQLITE_DONE && total > 0 && fflush(stdout) == 0) status = SQLITE_OK;
    else if (status == SQLITE_DONE) status = 1;
    api.finalize(statement);
    api.close(db);
    dlclose(api.handle);
    return status == SQLITE_OK ? 0 : 1;
}
