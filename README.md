
[![Not Maintained](https://img.shields.io/badge/Maintenance%20Level-Not%20Maintained-yellow.svg)](https://gist.github.com/cheerfulstoic/d107229326a01ff0f333a1d3476e068d)

# keychaineditor
KeychainEditor is a CLI to interact with iOS's [Keychain](https://developer.apple.com/library/ios/documentation/Security/Conceptual/keychainServConcepts/01introduction/introduction.html) on a jailbroken iDevice. Keychain is a secure storage provided by the iOS to save client-side secrets/certificates onto the device. KeychainEditor is useful to dump/edit/delete a keychain item. The tool will greatly help pentesters and security researches alike who would want to poke at application's keychain usage during iOS APT (Application Penetration Test). It should be noted that the tool currently supports Generic Passwords (Genp) only and can decode the new constrainsts applied on an item.

## Talk

For more information on the journey in decoding the `SecAccessControl` flags.

Slides: [bsides_ROC_2016-04-23.pdf](https://github.com/NitinJami/slides/blob/master/bsides_ROC_2016-04-23.pdf)

Video: [Exploring SecAccessControl Obj in iOS 9 Keychain](https://www.youtube.com/watch?v=JLwS-QZ2kWU)

## Features
1. Support for iOS8+ and the new changes in Keychain. Completely re-written in Swift.

2. Can now dump the actual `kSecAttrAccessControl` constraints used on a keychain item. (https://developer.apple.com/reference/security/secaccesscontrolcreateflags)

3. A search feature to limit the output to only what the user desired for. The search can be performed on Account, Service, AccessGroup or Accessibility values.
  * **./keychaineditor -f "WhenUnlocked"**

4. While updating the data for a keychain item using the `Edit` (-e) command. You can either pass a STRING or base64 encoded values for complex data.

4. Works with [idb!](http://www.idbtool.com/blog/2015/04/20/new-keychain-editor/)

*Note:* Please check --help command for more options/examples.

## Usage

**Attention:** command line arguments have been changed for simplicity.

```
USAGE: keychaineditor [commands]
Commands Description
  -v     version
  -f     Search. Requires a query string as the second argument.
  -e     Edit. Requires --account STRING --service STRING [--agroup STRING] --data (STRING or Base64)
  -d     Delete. Requires --account STRING --service STRING [--agroup STRING]
NOTES:
 * Account and Service names are used to uniquely identify a item. An optional AccessGroup can also be passed to identify the item.
 * If there is no Account name pass an empty string.
 * Search is from the following group {Account, Service, AccessGroup, Protection} and is case in-sensitive.
EXAMPLES:
 * To Dump entire keychain: $ keychaineditor
 * Limit dump by searching: $ keychaineditor -f "test"
 * Edit a keychain item:    $ keychaineditor -e --account "TestAccount" --service "TestService" --data "TestData"
 * Delete a keychain item:  $ keychaineditor -d --account "TestAccount" --service "TestService"
```

## Installation

Choose the package matching the device's jailbreak layout. Copy the `.deb` file to an authorized test device and install with `dpkg`:

| Layout | Package | Executable |
| --- | --- | --- |
| Rootful (legacy) | `keychaineditor.deb` | `/usr/local/bin/keychaineditor` |
| Rootless (iOS 15+) | `keychaineditor-rootless.deb` | `/var/jb/usr/bin/keychaineditor` |

For rootless, run as root in the device's bootstrap environment:

```
dpkg -i keychaineditor-rootless.deb
/var/jb/usr/bin/keychaineditor -v
/var/jb/usr/bin/keychaineditor -h
```

The help command currently exits with status 1. Use the full executable path if `/var/jb/usr/bin` is not in `PATH`.

For rootful, use `dpkg -i keychaineditor.deb`. Both packages have the same package identifier and are alternatives, not intended to be installed together.

To uninstall either package:

`dpkg -r com.nitin.keychaineditor`

*Note:* The rootless build uses the system Swift runtime provided by modern iOS and does not bundle Swift dylibs. Legacy rootful builds copy the matching old toolchain's Swift runtime into the package; do not reuse those old dylibs for a modern rootless build.

## Build Notes

### Rootless

Requires a full Xcode installation with an iPhoneOS SDK (not just Command Line Tools), `make`, `ldid`, `dpkg-deb` with `--root-owner-group` support, and Python 3. Select the Xcode developer directory with `xcode-select` if needed. `ldid` and `dpkg` can be installed via Homebrew.

```
make PACKAGE_SCHEME=rootless
make PACKAGE_SCHEME=rootless verify
```

`make THEOS_PACKAGE_SCHEME=rootless` is also accepted for convenience; this remains a standalone Makefile and does not require Theos. An explicit `PACKAGE_SCHEME` takes precedence. Parallel builds (`make -j4 PACKAGE_SCHEME=rootless verify`) are supported.

The rootless build targets arm64 and iOS 15.0 by default. It compiles with `swiftc`, signs using the existing `src/entitlements.xml`, and stages only the executable under `build/rootless/<configuration>/package/var/jb/usr/bin`. The configuration directory is keyed by deployment target, SDK path, and compiler paths so changing them cannot silently reuse incompatible objects. Packaging runs on each invocation to select the current configuration. Package metadata is generated from the existing control file with `Architecture: iphoneos-arm64`. The original rootful package and layout are not overwritten.

The `verify` target checks package layout, architecture, root ownership, executable permissions, Mach-O deployment version, system library/rpath dependencies, and the embedded Keychain entitlement. It is a static check: it neither runs the iOS executable nor accesses Keychain data. Entitlement extraction does not prove signature integrity or acceptance by the device's signing policy.

To remove only rootless build output:

`make PACKAGE_SCHEME=rootless clean`

### Rootful (legacy)

`make` (or `make PACKAGE_SCHEME=rootful`) retains the original iOS 9 / arm64 build and produces `keychaineditor.deb`. This path expects an older Xcode/Swift toolchain with the bundled Swift dylibs used by the original build; it is not a modern-Xcode compatibility guarantee. Testing this legacy path with Xcode 16.2 failed at `copylibs` because that toolchain no longer contains the expected old Swift dylibs.

Legacy 32-bit builds require a compatible old toolchain and SDK, with both `ARCH_FLAGS` and `TARGET` changed in the rootful section:

```
ARCH_FLAGS      =  -arch armv7s
TARGET          =  -target armv7s-apple-ios9
```

### Compatibility and device validation

The rootless package is intended for iOS 15+ jailbreak bootstraps using `/var/jb` and `iphoneos-arm64` packages. An arm64 command-line executable does not require an arm64e slice just because the device has an arm64e CPU. Layout compatibility does not imply compatibility with every bootstrap's signing and securityd policies.

The rootless build and static package checks have been tested with Xcode 16.2 / iPhoneOS SDK 18.2. A device smoke test on an iPad7,11 running iOS 18.7.10 with a Procursus `/var/jb` bootstrap passed: the package was unpacked into an isolated bootstrap temporary directory, `-v` printed version 2.2 and exited 0, and `-h` displayed help and exited 1 as expected. No package was installed and no real Keychain data was queried or modified during these tests. The source still produces warnings for deprecated accessibility constants; unsafe result casts and optional return-flag bridging have been removed.

On an authorized, isolated test device, first verify `-v` and `-h` to check executable loading, then validate only non-sensitive test items created by a test app. Check unlocked/locked behavior, access groups, and AccessControl-protected items. The existing wildcard Keychain entitlement must be honored by the jailbreak; root privileges alone do not guarantee cross-app access.

The AccessControl decoder no longer reads a private `SecAccessControl` memory layout. It optionally resolves `SecAccessControlGetConstraints` and `SecAccessControlGetRequirePassword`, validates object types, and safely reports `Unavailable` when the private API cannot be used. These are still private APIs: unknown operation/constraint formats are explicitly marked, and complete compatibility with all iOS versions is not guaranteed. Biometric constraints use `BiometryAny`/`BiometryCurrentSet` rather than assuming Touch ID hardware; those labels still depend on the known private constraint format.

### Query errors and regression tests

Queries accept a dictionary or an array of dictionaries without forced casts. A successful status with a nil result, unexpected result types, and mixed arrays are diagnosed instead of causing `trace trap`. Each query resets its result pointer. The return flags use boolean values that bridge to CFBoolean; regression tests inspect their actual CF types.

For dump and `-f`, stdout contains JSON, diagnostics go to stderr without including item data, and exit status is 1 when any query fails or returns a malformed result. Valid partial items are preserved, but the result is incomplete. `errSecItemNotFound` is normal empty output and does not fail. Exit status 0 still does not establish cross-app entitlement coverage.

Run the local synthetic regression suite:

```
make PACKAGE_SCHEME=rootless test
```

Build signed iOS regression executables, without uploading or running them automatically:

```
make PACKAGE_SCHEME=rootless test-device
```

They are created as `build/rootless/<configuration>/compatibility` and `compatibility-disabled`. Both use only injected synthetic queries and in-memory AccessControl objects: they do not call real Keychain queries, additions, updates, or deletions. The disabled variant simulates missing private APIs. `scripts/test-compatibility.py` also verifies synthetic dump/search JSON, stderr, and exit statuses.

The suite passed 108 checks with private APIs available and 101 checks with them disabled, both on macOS and on the iOS 18.7.10 test iPad. It also checks malformed fractional ACL thresholds and output-write failure handling. In-memory objects covered no flags, UserPresence, DevicePasscode, BiometryAny, BiometryCurrentSet, ApplicationPassword, PrivateKeyUsage, and PrivateKeyUsage + DevicePasscode. ApplicationPassword now appears in the decoded output and PrivateKeyUsage no longer traps. Tests of nil and partial results returned status 1 with valid JSON; item-not-found returned status 0. These tests verify the compatibility boundaries, not actual protected Keychain item access or every private constraint format.

**Attention:** running without arguments attempts to dump all accessible Generic Password items. `-f` filters the result after querying Keychain, not the query itself. Do not use production secrets for validation.

## Deleting items

Delete one item, uniquely identified by account and service (add `--agroup` when the same pair exists in several groups):

```
keychaineditor -d --account "adjust_uuid" --service "deviceInfo" --agroup "N5GGUUB3U6.in.pocketful.ios"
```

Delete every visible item in an access group with `-dg`. Because this is destructive, it requires the confirmation flag, and the Foundation argument parser registers flags only when they carry a value, so the required form is `--yes 1` (a bare `--yes` is ignored and triggers the preview):

```
keychaineditor -dg --agroup "2MF2YLGLKJ.io.cex.app"            # preview only, exits 1
keychaineditor -dg --agroup "2MF2YLGLKJ.io.cex.app" --yes 1    # deletes, then re-queries
```

The preview lists each item's account and service before refusal. After `--yes 1`, the tool deletes with a class + access-group query (`SecItemDelete` rejects `kSecMatchLimit`) and re-queries the group; it reports success only when the group is empty. Items in slices rejected by the platform (for example `-25293` on iOS 18) may remain; the re-query catches that and exits 1 with a warning.

### Known iOS 18 limitation: silent empty query results

On a jailbroken iOS 18.7.10 iPad with a Procursus rootless bootstrap, extensive on-device probing found that the tool's queries return success (0) with a nil result for every query shape, even after the same process successfully writes and deletes an item, and even with an explicit access group. Direct database inspection confirms the device's keychain contains thousands of items across roughly 90 access groups, including items in the queried group. `SecTaskCopyValueForEntitlement` shows the wildcard `keychain-access-groups = ["*"]` entitlement is visible to securityd, but securityd silently returns no data instead of expanding the wildcard or returning an error. An ad-hoc binary without the entitlement correctly fails with `-34018`, so entitlements are being enforced; the wildcard expansion itself is what fails silently. Restarting securityd did not change this behavior.

This is a securityd policy or platform-behavior change on iOS 18 that this tool's default entitlement strategy does not overcome. The observed behavior (write succeeds, every read returns success with no data) is consistent with securityd accepting the client but not expanding the wildcard entitlement to a concrete group list. Restarting securityd did not change this behavior. The tool reports these conditions on stderr with exit status 1 instead of crashing.

### Workaround: concrete per-device entitlements (`ENTITLEMENTS=`)

Signing the tool with a concrete `keychain-access-groups` list restores full query capability on iOS 18. On the test iPad, a build signed with explicit group strings (one per group present in the device keychain) read back 903 items across 69 groups, including all items of `N5GGUUB3U6.in.pocketful.ios`. A wildcard `["*"]` entitlement is treated differently from an explicit list even when the same groups are involved.

Generate `src/entitlements-device.xml` from the device's actual access groups (root access to `/var/Keychains/keychain-2.db` is required to list them) and build with:

```
make PACKAGE_SCHEME=rootless ENTITLEMENTS=src/entitlements-device.xml verify
```

`ENTITLEMENTS` defaults to `src/entitlements.xml` for the portable wildcard build. Both builds are `iphoneos-arm64` and pass static verification; the concrete list is device-specific and does not transfer to other devices.

### Refreshing device entitlements

The concrete group list is a snapshot: apps installed or used later create new access groups that are not covered. Re-run the full refresh (re-export groups, rebuild, reinstall) with one command from the repository root on the Mac:

```
python3 scripts/refresh-device-entitlements.py
```

It uploads the read-only helper `scripts/device/kc-dump-groups-arm64` (lists access groups from the keychain database, without touching item data), regenerates `src/entitlements-device.xml`, rebuilds with verification, installs over `dpkg`, and prints `+`/`-` group diffs. Use `--skip-install` to rebuild without reinstalling and `--host <alias>` for a different SSH alias than `ipad`.

On a device that already has the rootless binary installed, the same refresh can run entirely on the iPad. Install Procursus `ldid` once:

```
apt install ldid
```

Then use the built-in short command:

```
keychaineditor -r
keychaineditor -r -f "io.new.app"
```

`-r` reads only distinct `genp.agrp` values from `/var/Keychains/keychain-2.db`, generates a concrete entitlement plist, signs a temporary copy with `/var/jb/usr/bin/ldid` (or `/var/jb/usr/local/bin/ldid`), and atomically replaces the executable only after signing succeeds. With remaining arguments, it re-execs the new signed binary after removing `-r`; without remaining arguments it exits after reporting success. A missing `ldid`, empty group list, database failure, or signing failure leaves the existing executable untouched. The command requires root and does not read item data.

This is intended for the installed rootless executable and does not produce a `.deb`. The Mac script remains useful for building and distributing a fresh package. `-r` is deliberately explicit; ordinary queries never re-sign the executable automatically.

Two residual limitations were observed on iOS 18.7.10. Queries restricted to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` return `-25293` (authorization failure) on this bootstrap, so that accessibility slice is skipped and reported on stderr; the other six slices return data. Four `com.apple.*` system groups return `-25300` even when explicitly signed into the entitlement list, and their items are excluded from the dump. The readable total (903 items across 69 groups) therefore differs from the raw database count (1187 genp rows).
