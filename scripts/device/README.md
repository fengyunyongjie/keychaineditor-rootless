# Device helper: kc-dump-groups-arm64

Read-only iOS utility that prints every distinct Generic Password access group
(`agrp`) in `/var/Keychains/keychain-2.db`, one per line. It is signed ad-hoc
without entitlements because it only reads the SQLite file directly; it never
talks to securityd and never reads or writes item data.

## Rebuild

```sh
xcrun --sdk iphoneos clang \
  -target arm64-apple-ios15.0 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -framework Security -framework CoreFoundation \
  scripts/device/kc-dump-groups.c -o scripts/device/kc-dump-groups-arm64
ldid -S scripts/device/kc-dump-groups-arm64
```

The same database scan is compiled into the main `keychaineditor -r` command;
this standalone helper remains for the Mac-side refresh script.