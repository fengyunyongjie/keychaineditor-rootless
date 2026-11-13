#include "refreshKeychainGroups.h"
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#define SQLITE_OK 0
#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_OPEN_READONLY 0x00000001
#define GROUP_BUFFER_LIMIT (1024 * 1024)
#define XML_BUFFER_LIMIT (2 * 1024 * 1024)

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

static bool load_sqlite(SQLiteAPI *api) {
    memset(api, 0, sizeof(*api));
    api->handle = dlopen("/usr/lib/libsqlite3.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (api->handle == NULL) return false;
    api->open = (sqlite3_open_v2_fn)dlsym(api->handle, "sqlite3_open_v2");
    api->close = (sqlite3_close_fn)dlsym(api->handle, "sqlite3_close");
    api->prepare = (sqlite3_prepare_v2_fn)dlsym(api->handle, "sqlite3_prepare_v2");
    api->step = (sqlite3_step_fn)dlsym(api->handle, "sqlite3_step");
    api->finalize = (sqlite3_finalize_fn)dlsym(api->handle, "sqlite3_finalize");
    api->column_text = (sqlite3_column_text_fn)dlsym(api->handle, "sqlite3_column_text");
    if (api->open == NULL || api->close == NULL || api->prepare == NULL ||
        api->step == NULL || api->finalize == NULL || api->column_text == NULL) {
        dlclose(api->handle);
        memset(api, 0, sizeof(*api));
        return false;
    }
    return true;
}

static bool append_bytes(char **buffer, size_t *length, size_t *capacity,
                         const char *bytes, size_t byte_count, size_t limit) {
    if (byte_count > limit || *length > limit - byte_count) return false;
    if (*length + byte_count + 1 > *capacity) {
        size_t new_capacity = *capacity == 0 ? 4096 : *capacity;
        while (new_capacity < *length + byte_count + 1) {
            if (new_capacity > limit / 2) {
                new_capacity = limit;
                break;
            }
            new_capacity *= 2;
        }
        char *new_buffer = realloc(*buffer, new_capacity);
        if (new_buffer == NULL) return false;
        *buffer = new_buffer;
        *capacity = new_capacity;
    }
    memcpy(*buffer + *length, bytes, byte_count);
    *length += byte_count;
    (*buffer)[*length] = '\0';
    return true;
}

static bool append_string(char **buffer, size_t *length, size_t *capacity,
                          const char *value, size_t limit) {
    return append_bytes(buffer, length, capacity, value, strlen(value), limit);
}

char *keychain_copy_access_groups(void) {
    SQLiteAPI api;
    if (!load_sqlite(&api)) return NULL;

    void *database = NULL;
    if (api.open("/var/Keychains/keychain-2.db", &database,
                 SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        dlclose(api.handle);
        return NULL;
    }

    void *statement = NULL;
    const char *tail = NULL;
    const char *sql = "SELECT DISTINCT agrp FROM genp WHERE agrp IS NOT NULL ORDER BY agrp";
    if (api.prepare(database, sql, -1, &statement, &tail) != SQLITE_OK) {
        api.close(database);
        dlclose(api.handle);
        return NULL;
    }

    char *groups = NULL;
    size_t length = 0;
    size_t capacity = 0;
    int status = SQLITE_OK;
    while ((status = api.step(statement)) == SQLITE_ROW) {
        const unsigned char *group = api.column_text(statement, 0);
        if (group != NULL && group[0] != '\0') {
            size_t group_length = strlen((const char *)group);
            if (!append_bytes(&groups, &length, &capacity, (const char *)group,
                              group_length, GROUP_BUFFER_LIMIT) ||
                !append_bytes(&groups, &length, &capacity, "\n", 1,
                              GROUP_BUFFER_LIMIT)) {
                free(groups);
                groups = NULL;
                break;
            }
        }
    }
    if (status != SQLITE_DONE || length == 0) {
        free(groups);
        groups = NULL;
    }

    api.finalize(statement);
    api.close(database);
    dlclose(api.handle);
    return groups;
}

static bool append_xml_group(char **xml, size_t *length, size_t *capacity,
                             const char *group, size_t group_length) {
    if (!append_string(xml, length, capacity, "\t\t\t<string>", XML_BUFFER_LIMIT)) return false;
    for (size_t i = 0; i < group_length; i++) {
        const char *replacement = NULL;
        char character[2] = { group[i], '\0' };
        switch ((unsigned char)group[i]) {
        case '&': replacement = "&amp;"; break;
        case '<': replacement = "&lt;"; break;
        case '>': replacement = "&gt;"; break;
        case '"': replacement = "&quot;"; break;
        case '\'': replacement = "&apos;"; break;
        default:
            if ((unsigned char)group[i] < 0x20 && group[i] != '\t') return false;
            replacement = character;
        }
        if (!append_string(xml, length, capacity, replacement, XML_BUFFER_LIMIT)) return false;
    }
    return append_string(xml, length, capacity, "</string>\n", XML_BUFFER_LIMIT);
}

static char *groups_to_entitlements(const char *groups) {
    if (groups == NULL || groups[0] == '\0') return NULL;

    char *xml = NULL;
    size_t length = 0;
    size_t capacity = 0;
    const char *header =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\"><dict>\n"
        "\t<key>keychain-access-groups</key>\n\t<array>\n";
    if (!append_string(&xml, &length, &capacity, header, XML_BUFFER_LIMIT)) {
        free(xml);
        return NULL;
    }

    const char *start = groups;
    const char *end = groups;
    while (*start != '\0') {
        while (*end != '\0' && *end != '\n') end++;
        if (end == start || !append_xml_group(&xml, &length, &capacity,
                                                start, (size_t)(end - start))) {
            free(xml);
            return NULL;
        }
        if (*end == '\0') break;
        start = end + 1;
        end = start;
    }
    if (!append_string(&xml, &length, &capacity, "\t</array>\n</dict></plist>\n",
                       XML_BUFFER_LIMIT)) {
        free(xml);
        return NULL;
    }
    return xml;
}

static bool copy_file(const char *source, const char *destination) {
    int input = open(source, O_RDONLY);
    if (input < 0) return false;
    int output = open(destination, O_WRONLY | O_CREAT | O_EXCL, 0755);
    if (output < 0) {
        close(input);
        return false;
    }

    char buffer[16384];
    ssize_t count;
    bool success = true;
    while ((count = read(input, buffer, sizeof(buffer))) > 0) {
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t written = write(output, buffer + offset, (size_t)(count - offset));
            if (written <= 0) {
                success = false;
                break;
            }
            offset += written;
        }
        if (!success) break;
    }
    if (count < 0 || fsync(output) != 0) success = false;
    close(output);
    close(input);
    if (!success) unlink(destination);
    return success;
}

static int run_ldid(const char *ldid_path, const char *entitlements,
                    const char *temporary_binary) {
    char sign_argument[PATH_MAX + 3];
    if (snprintf(sign_argument, sizeof(sign_argument), "-S%s", entitlements)
        >= (int)sizeof(sign_argument)) return E2BIG;

    char *const arguments[] = {
        (char *)ldid_path, sign_argument, (char *)temporary_binary, NULL
    };
    pid_t child = 0;
    int status = posix_spawn(&child, ldid_path, NULL, NULL, arguments, environ);
    if (status != 0) return status;
    if (waitpid(child, &status, 0) < 0) return errno;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) return EACCES;
    return 0;
}

static char *copy_current_executable_path(void) {
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    if (size == 0) return NULL;
    char *path = malloc(size);
    if (path == NULL || _NSGetExecutablePath(path, &size) != 0) {
        free(path);
        return NULL;
    }
    char resolved[PATH_MAX];
    if (realpath(path, resolved) == NULL) {
        free(path);
        return NULL;
    }
    free(path);
    return strdup(resolved);
}

static int refresh_executable(const char *executable_path) {
    if (geteuid() != 0 || executable_path == NULL || executable_path[0] != '/') return EPERM;

    char *groups = keychain_copy_access_groups();
    char *entitlements = groups_to_entitlements(groups);
    free(groups);
    if (entitlements == NULL) return EINVAL;

    char entitlement_template[PATH_MAX];
    char binary_template[PATH_MAX];
    if (snprintf(entitlement_template, sizeof(entitlement_template),
                 "%s.refresh-entitlements.XXXXXX", executable_path) >= (int)sizeof(entitlement_template) ||
        snprintf(binary_template, sizeof(binary_template),
                 "%s.refresh-binary.XXXXXX", executable_path) >= (int)sizeof(binary_template)) {
        free(entitlements);
        return ENAMETOOLONG;
    }

    int entitlement_fd = mkstemp(entitlement_template);
    if (entitlement_fd < 0) {
        free(entitlements);
        return errno;
    }
    fchmod(entitlement_fd, 0600);
    size_t xml_length = strlen(entitlements);
    bool wrote = write(entitlement_fd, entitlements, xml_length) == (ssize_t)xml_length;
    wrote = wrote && fsync(entitlement_fd) == 0;
    close(entitlement_fd);
    free(entitlements);
    if (!wrote) {
        unlink(entitlement_template);
        return EIO;
    }

    int binary_fd = mkstemp(binary_template);
    if (binary_fd < 0) {
        unlink(entitlement_template);
        return errno;
    }
    close(binary_fd);
    unlink(binary_template);
    if (!copy_file(executable_path, binary_template)) {
        unlink(entitlement_template);
        return EIO;
    }

    const char *ldid_paths[] = {
        "/var/jb/usr/bin/ldid", "/var/jb/usr/local/bin/ldid", NULL
    };
    int status = ENOENT;
    for (size_t i = 0; ldid_paths[i] != NULL; i++) {
        if (access(ldid_paths[i], X_OK) == 0) {
            status = run_ldid(ldid_paths[i], entitlement_template, binary_template);
            break;
        }
    }
    unlink(entitlement_template);
    if (status != 0) {
        unlink(binary_template);
        return status;
    }
    if (rename(binary_template, executable_path) != 0) {
        status = errno;
        unlink(binary_template);
        return status;
    }
    return 0;
}

int keychain_refresh_current_executable_and_exec(int argc, char *const argv[]) {
    char *executable_path = copy_current_executable_path();
    if (executable_path == NULL) return ENOENT;

    int status = refresh_executable(executable_path);
    if (status != 0) {
        free(executable_path);
        return status;
    }

    int remaining = 0;
    for (int i = 1; i < argc; i++) {
        if (argv[i] != NULL && strcmp(argv[i], "-r") != 0) remaining++;
    }
    if (remaining == 0) {
        free(executable_path);
        return 0;
    }

    char **new_arguments = calloc((size_t)remaining + 2, sizeof(char *));
    if (new_arguments == NULL) {
        free(executable_path);
        return ENOMEM;
    }
    new_arguments[0] = executable_path;
    int next = 1;
    for (int i = 1; i < argc; i++) {
        if (argv[i] != NULL && strcmp(argv[i], "-r") != 0) {
            new_arguments[next++] = argv[i];
        }
    }
    new_arguments[next] = NULL;
    execv(executable_path, new_arguments);
    status = errno;
    free(new_arguments);
    free(executable_path);
    return status;
}
