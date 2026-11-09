#!/bin/bash
# Verify an exported IPA, export directory, Payload directory, or Pearls.app.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
[ "$#" -eq 1 ] || fail 'Usage: TEAM_ID=... scripts/verify-testflight.sh /path/to/export-or.ipa'
require_macos_xcode
require_team
command -v python3 >/dev/null 2>&1 || fail 'python3 is required to inspect the export.'
python3 - "$1" "$TEAM_ID" "${EXPECTED_IOS_BUNDLE_ID:-com.briggskellogg.pearls}" "${BUILD_NUMBER:-}" <<'PY'
from pathlib import Path, PurePosixPath
from datetime import datetime, timezone
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

target = Path(sys.argv[1]).expanduser().resolve()
team, expected_id, expected_build = sys.argv[2:]

def require(condition, message):
    if not condition:
        raise SystemExit("Pearls: " + message)

def plist_command(arguments):
    # The :- display form emits XML, including on Xcode versions whose default
    # entitlement display is a human-readable dictionary instead of a plist.
    result = subprocess.run(arguments, check=True, capture_output=True)
    return plistlib.loads(result.stdout)

with tempfile.TemporaryDirectory(prefix="pearls-verify-") as temporary:
    if target.is_dir() and target.name != "Pearls.app" and not (target / "Payload/Pearls.app").is_dir() and not (target / "Pearls.app").is_dir():
        candidates = list(target.glob("*.ipa"))
        require(len(candidates) == 1, "Export directory must contain exactly one IPA.")
        target = candidates[0]
    if target.is_file() and target.suffix == ".ipa":
        with zipfile.ZipFile(target) as archive:
            for entry in archive.infolist():
                path = PurePosixPath(entry.filename)
                require(not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename,
                        "Unsafe path in IPA.")
                require(not stat.S_ISLNK(entry.external_attr >> 16), "Symlinks are not accepted in an IPA.")
            archive.extractall(temporary)
        app = Path(temporary) / "Payload/Pearls.app"
    elif target.is_dir():
        app = target if target.name == "Pearls.app" else target / "Pearls.app"
        if not app.is_dir():
            app = target / "Payload/Pearls.app"
    else:
        raise SystemExit("Pearls: Supply an existing IPA or exported app directory.")
    require(app.is_dir(), "Export does not contain Pearls.app.")
    versions, builds, groups = set(), set(), set()
    for product, bundle_id in [(app, expected_id), (app / "PlugIns/PearlsShare.appex", expected_id + ".share")]:
        require(product.is_dir(), "Missing app or share extension.")
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(product)], check=True)
        info = plistlib.loads((product / "Info.plist").read_bytes())
        require(info.get("CFBundleIdentifier") == bundle_id, "Unexpected bundle identifier in " + product.name)
        require(info.get("DTPlatformName") == "iphoneos", "Expected iPhone device products.")
        build, version = info.get("CFBundleVersion"), info.get("CFBundleShortVersionString")
        require(isinstance(build, str) and re.fullmatch(r"[1-9][0-9]*", build), "Invalid build number.")
        require(not expected_build or build == expected_build, "Exported build number does not match BUILD_NUMBER.")
        require(isinstance(version, str) and bool(version.strip()), "Missing marketing version.")
        builds.add(build)
        versions.add(version)
        group = info.get("PearlsAppGroup")
        require(isinstance(group, str) and group.startswith("group.") and len(group) > 6
                and not re.search(r"\s|\$[({]", group), "Missing or unresolved PearlsAppGroup.")
        groups.add(group)
        signed = plist_command(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(product)])
        profile = plist_command(["/usr/bin/security", "cms", "-D", "-i", str(product / "embedded.mobileprovision")])
        require(team in profile.get("TeamIdentifier", []), "Provisioning profile belongs to another team.")
        expiry = profile.get("ExpirationDate")
        require(isinstance(expiry, datetime) and expiry.replace(tzinfo=timezone.utc) > datetime.now(timezone.utc), "Provisioning profile has expired.")
        require(not profile.get("ProvisionedDevices") and not profile.get("ProvisionsAllDevices"), "Expected an App Store distribution profile.")
        provisioned = profile.get("Entitlements", {})
        for label, entitlements in [("signature", signed), ("profile", provisioned)]:
            require(entitlements.get("application-identifier") == team + "." + bundle_id, "Unexpected application identifier in " + label)
            require(entitlements.get("com.apple.developer.team-identifier") == team, "Unexpected team in " + label)
            require(entitlements.get("get-task-allow") is False, "Distribution " + label + " must disable get-task-allow.")
            require(entitlements.get("beta-reports-active") is True, "Missing TestFlight capability in " + label)
            app_groups = entitlements.get("com.apple.security.application-groups")
            require(isinstance(app_groups, list) and group in app_groups, "Required App Group missing from " + product.name + " " + label)
        require(set(signed["com.apple.security.application-groups"]).issubset(provisioned["com.apple.security.application-groups"]), "Profile does not permit every signed App Group.")
    require(len(versions) == len(builds) == len(groups) == 1, "App and extension version, build, or App Group differ.")
    print("Verified TestFlight export: " + expected_id + " " + next(iter(versions)) + " (" + next(iter(builds)) + ")")
    print("Both signatures and distribution profiles permit " + next(iter(groups)) + ". No upload performed.")
PY
