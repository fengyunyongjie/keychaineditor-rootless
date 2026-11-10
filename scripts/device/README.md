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
  /tmp/kc-dump-groups.c -o scripts/device/kc-dump-groups-arm64
ldid -S scripts/device/kc-dump-groups-arm64
```

The source lives at `/tmp/kc-dump-groups.c` in the session that produced the
binary; it is intentionally not committed because it is small and the committed
binary is ad-hoc signed. Rebuild from the snippet in
`scripts/refresh-device-entitlements.py` history if needed.
