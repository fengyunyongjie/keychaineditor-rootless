#!/usr/bin/env python3
"""Refresh device-specific keychain entitlements and reinstall on a jailbroken iPad.

Workflow:
1. Upload scripts/device/kc-dump-groups-arm64 to the device (via `ssh ipad`).
2. Run it read-only to list all Generic Password access groups.
3. Regenerate src/entitlements-device.xml from that list.
4. Rebuild the rootless package with ENTITLEMENTS=src/entitlements-device.xml.
5. Install the package on the device.

Usage:
  python3 scripts/refresh-device-entitlements.py [--host ipad] [--skip-install]
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ENTITLEMENTS = REPO / "src" / "entitlements-device.xml"
EXPORT_TOOL = REPO / "scripts" / "device" / "kc-dump-groups-arm64"
PLIST_HEADER = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
\t<dict>
\t\t<key>keychain-access-groups</key>
\t\t<array>
"""
PLIST_FOOTER = """\t\t</array>
\t</dict>
</plist>
"""


def escape(group: str) -> str:
    return group.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def run(*command, input_text=None):
    result = subprocess.run(command, input=input_text, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"Command failed ({' '.join(command)}): {result.stderr.strip()}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="ipad", help="SSH host alias of the jailbroken device")
    parser.add_argument("--skip-install", action="store_true", help="build but do not reinstall")
    args = parser.parse_args()

    if not EXPORT_TOOL.is_file():
        sys.exit(f"Missing {EXPORT_TOOL}. Build it first (see scripts/device/README.md).")

    with tempfile.TemporaryDirectory(prefix="kc-refresh-") as tmp:
        tmp_path = Path(tmp)
        remote_tmp = "/var/jb/tmp/keychaineditor-refresh"
        run("ssh", "-o", "BatchMode=yes", args.host,
            f"mkdir -p {remote_tmp} && chmod 700 {remote_tmp}")
        run("scp", "-o", "BatchMode=yes", str(EXPORT_TOOL), f"{args.host}:{remote_tmp}/")

        group_list = run("ssh", "-o", "BatchMode=yes", args.host,
                         f"chmod 755 {remote_tmp}/kc-dump-groups-arm64 && {remote_tmp}/kc-dump-groups-arm64")
        run("ssh", "-o", "BatchMode=yes", args.host, f"rm -rf {remote_tmp}")

        groups = sorted(line.strip() for line in group_list.splitlines() if line.strip())
        if not groups:
            sys.exit("Device returned no access groups; refusing to write empty entitlements.")

        old_groups = set()
        if ENTITLEMENTS.is_file():
            old_groups = set(line.strip().removeprefix("\t\t\t<string>").removesuffix("</string>")
                             for line in ENTITLEMENTS.read_text().splitlines()
                             if line.strip().startswith("\t\t\t<string>"))
        added = sorted(set(groups) - old_groups)
        removed = sorted(old_groups - set(groups))

        plist = PLIST_HEADER + "".join(f"\t\t\t<string>{escape(group)}</string>\n" for group in groups) + PLIST_FOOTER
        ENTITLEMENTS.write_text(plist)
        print(f"entitlements-device.xml: {len(groups)} groups (+{len(added)} new, -{len(removed)} removed)")
        for group in added:
            print("  +", group)
        for group in removed:
            print("  -", group)

        print("Building rootless package...")
        run("make", "PACKAGE_SCHEME=rootless", f"ENTITLEMENTS={ENTITLEMENTS}", "-j4", "verify")
        package = REPO / "keychaineditor-rootless.deb"

        if args.skip_install:
            print(f"Build complete: {package}")
            return

        remote_deb = "/var/tmp/keychaineditor-rootless.deb"
        run("scp", "-o", "BatchMode=yes", str(package), f"{args.host}:{remote_deb}")
        run("ssh", "-o", "BatchMode=yes", args.host,
            f"dpkg -i {remote_deb} && /var/jb/usr/bin/keychaineditor -v")
        print("Installed. Query with: /var/jb/usr/bin/keychaineditor -f <keyword>")


if __name__ == "__main__":
    main()
