import argparse
import io
from pathlib import Path
import plistlib
import re
import subprocess
import tarfile
import tempfile


def run(*command):
    return subprocess.check_output(command)


def require(condition, message):
    if not condition:
        raise SystemExit("Verification failed: " + message)


def system_path(path):
    return path.startswith(("/usr/lib/", "/System/Library/"))


def verify(package):
    architecture = run("dpkg-deb", "-f", str(package), "Architecture").decode().strip()
    require(architecture == "iphoneos-arm64", "incorrect Debian architecture")

    payload = run("dpkg-deb", "--fsys-tarfile", str(package))
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
        members = archive.getmembers()
        files = [member for member in members if not member.isdir()]
        require(len(files) == 1, "unexpected package files or bundled runtime")
        binary = files[0]
        require(binary.name == "./var/jb/usr/bin/keychaineditor" and binary.isfile(),
                "incorrect rootless executable path or type")
        require(binary.mode == 0o755, "executable must have mode 755")
        require(all(member.uid == 0 and member.gid == 0 for member in members),
                "package files must be owned by root")
        directories = {".", "./var", "./var/jb", "./var/jb/usr", "./var/jb/usr/bin"}
        require(all(member.name.rstrip("/") in directories for member in members if member.isdir()),
                "unexpected package directories")
        data = archive.extractfile(binary).read()

    with tempfile.TemporaryDirectory(prefix="keychaineditor-verify-") as directory:
        executable = Path(directory) / "keychaineditor"
        executable.write_bytes(data)
        archs = run("xcrun", "lipo", "-archs", str(executable)).decode().strip()
        require(archs == "arm64", "executable must contain only arm64")

        commands = run("xcrun", "otool", "-l", str(executable)).decode()
        blocks = re.split(r"Load command \d+\n", commands)[1:]
        versions = [block for block in blocks if "cmd LC_BUILD_VERSION\n" in block]
        require(len(versions) == 1, "missing iOS build version")
        require(re.search(r"platform\s+(?:2|IOS)\b", versions[0]) is not None,
                "executable is not built for iOS devices")
        minos = re.search(r"minos\s+(\d+)\.(\d+)", versions[0])
        require(minos is not None and int(minos[1]) >= 15, "deployment target must be iOS 15+")

        rpaths = []
        dependencies = []
        dylib_commands = {"LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB", "LC_LOAD_UPWARD_DYLIB"}
        for block in blocks:
            command = re.search(r"\bcmd (\S+)", block)
            if command and command[1] == "LC_RPATH":
                path = re.search(r"\bpath (.+) \(offset", block)
                require(path is not None, "invalid rpath load command")
                rpaths.append(path[1])
            elif command and command[1] in dylib_commands:
                name = re.search(r"\bname (.+) \(offset", block)
                require(name is not None, "invalid dylib load command")
                dependencies.append(name[1])

        require(dependencies, "missing dynamic library dependencies")
        require(all(system_path(path) for path in rpaths), "non-system runtime search path")
        for dependency in dependencies:
            require(system_path(dependency) or dependency.startswith("@rpath/"),
                    "non-system dependency: " + dependency)
            if dependency.startswith("@rpath/"):
                require("/usr/lib/swift" in rpaths,
                        "@rpath dependency has no system Swift runtime search path")

        entitlements = plistlib.loads(run("ldid", "-e", str(executable)))
        groups = entitlements.get("keychain-access-groups")
        require(isinstance(groups, list) and len(groups) >= 1
                and all(isinstance(group, str) and group for group in groups),
                "missing keychain-access-groups entitlement")

    print("Rootless package verified: iphoneos-arm64, /var/jb/usr/bin, arm64, iOS "
          + minos[0].split()[1] + "+, system runtime, embedded entitlements.")
    print("Signature integrity, device execution, and Keychain permissions are not verified by this check.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Statically verify a rootless KeychainEditor package.")
    parser.add_argument("package", type=Path)
    args = parser.parse_args()
    verify(args.package.resolve())
