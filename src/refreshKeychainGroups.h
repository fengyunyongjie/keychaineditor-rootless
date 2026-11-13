#include <stdbool.h>
#include <sys/types.h>

// Generate the current device's sorted, distinct Generic Password agrp list.
// The returned newline-separated buffer is heap allocated and must be freed.
char *keychain_copy_access_groups(void);

// Refresh the running executable's concrete keychain entitlement. If argv
// contains arguments after -r, the function re-execs the refreshed binary
// without -r. Returns 0 on refresh-only success and a nonzero errno value on
// failure; the original executable remains untouched on failure.
int keychain_refresh_current_executable_and_exec(int argc, char *const argv[]);
