#ifndef bridgingheader_h
#define bridgingheader_h

#include <stdbool.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>

/* Borrowed result; valid while access_control remains alive. */
CFDictionaryRef getOperations(CFTypeRef access_control);

/* Returns false for invalid input or when the optional getter is unavailable. */
bool accessControlRequiresPassword(CFTypeRef access_control);

/* Reports symbol availability, not whether an object has constraints. */
bool accessControlOperationsAvailable(void);

#endif /* bridgingheader_h */
