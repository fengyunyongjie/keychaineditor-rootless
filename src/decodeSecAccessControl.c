#include "bridgingheader.h"
#include "SecAccessControlPriv.h"
#include <dlfcn.h>

/* Signatures match SecAccessControlPriv.h; neither getter transfers ownership. */
typedef CFDictionaryRef (*GetConstraintsFunc)(SecAccessControlRef);
typedef bool (*GetRequirePasswordFunc)(SecAccessControlRef);

static GetConstraintsFunc resolveGetConstraints(void) {
#ifdef KEYCHAINEDITOR_DISABLE_PRIVATE_API
    return NULL;
#else
    return (GetConstraintsFunc)dlsym(RTLD_DEFAULT, "SecAccessControlGetConstraints");
#endif
}

static GetRequirePasswordFunc resolveGetRequirePassword(void) {
#ifdef KEYCHAINEDITOR_DISABLE_PRIVATE_API
    return NULL;
#else
    return (GetRequirePasswordFunc)dlsym(RTLD_DEFAULT, "SecAccessControlGetRequirePassword");
#endif
}

CFDictionaryRef getOperations(CFTypeRef access_control) {
    if (access_control == NULL || CFGetTypeID(access_control) != SecAccessControlGetTypeID()) {
        return NULL;
    }

    GetConstraintsFunc getter = resolveGetConstraints();
    if (getter == NULL) {
        return NULL;
    }

    CFDictionaryRef operations = getter((SecAccessControlRef)access_control);
    if (operations == NULL || CFGetTypeID(operations) != CFDictionaryGetTypeID()) {
        return NULL;
    }

    return operations;
}

bool accessControlRequiresPassword(CFTypeRef access_control) {
    if (access_control == NULL || CFGetTypeID(access_control) != SecAccessControlGetTypeID()) {
        return false;
    }

    GetRequirePasswordFunc getter = resolveGetRequirePassword();
    if (getter == NULL) {
        return false;
    }

    return getter((SecAccessControlRef)access_control);
}

bool accessControlOperationsAvailable(void) {
    return resolveGetConstraints() != NULL;
}
