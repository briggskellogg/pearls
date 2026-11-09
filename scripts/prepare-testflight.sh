#!/bin/bash
# Prepare and verify a local App Store export; never upload or invite testers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
[ "$#" -eq 0 ] || fail 'Configure TEAM_ID, BUILD_NUMBER and optional output paths through environment variables.'
require_submission_xcode
require_team
load_apple_auth
command -v python3 >/dev/null 2>&1 || fail 'python3 is required to preserve and verify entitlements.'
[[ "${BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]] || fail 'Set BUILD_NUMBER to a positive, unused App Store build number.'
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/ios/Pearls-TestFlight-build-$BUILD_NUMBER.xcarchive}"
IOS_DERIVED_DATA="${IOS_DERIVED_DATA:-$BUILD_ROOT/ios-derived}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_ROOT/ios/testflight-export-build-$BUILD_NUMBER}"
case "$ARCHIVE_PATH" in /*.xcarchive) ;; *) fail 'ARCHIVE_PATH must be an absolute .xcarchive path.' ;; esac
case "$IOS_DERIVED_DATA" in /*) ;; *) fail 'IOS_DERIVED_DATA must be absolute.' ;; esac
case "$EXPORT_PATH" in /*) ;; *) fail 'EXPORT_PATH must be absolute.' ;; esac
[ ! -e "$ARCHIVE_PATH" ] && [ ! -L "$ARCHIVE_PATH" ] || fail "Archive already exists; left untouched: $ARCHIVE_PATH"
[ ! -e "$EXPORT_PATH" ] && [ ! -L "$EXPORT_PATH" ] || fail "Export already exists; left untouched: $EXPORT_PATH"
EXPECTED_IOS_BUNDLE_ID="${EXPECTED_IOS_BUNDLE_ID:-com.briggskellogg.pearls}"

mkdir -p "$BUILD_ROOT"
SOURCE_RECORD_DIR="$(mktemp -d "$BUILD_ROOT/release-source.XXXXXX")"
trap 'rm -rf "$SOURCE_RECORD_DIR"' EXIT
python3 "$SCRIPT_DIR/package-release.py" capture \
  --output "$SOURCE_RECORD_DIR/source.json" --build-number "$BUILD_NUMBER"

bash "$PEARLS_ROOT/BuildSupport/prepare-assets.sh"
mkdir -p "$(dirname "$ARCHIVE_PATH")" "$(dirname "$EXPORT_PATH")"
# Development provisioning needs a registered phone. Build the device product
# unsigned, then retain source capabilities in an ad-hoc signature for export.
xcodebuild \
  -project "$PROJECT_PATH" -scheme "$IOS_SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$IOS_DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

python3 - "$PEARLS_ROOT" "$ARCHIVE_PATH" "$TEAM_ID" "$BUILD_NUMBER" "$EXPECTED_IOS_BUNDLE_ID" <<'PY'
import plistlib
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root, archive = map(Path, sys.argv[1:3])
team, build, expected_id = sys.argv[3:]
app = archive / "Products/Applications/Pearls.app"
products = [(app / "PlugIns/PearlsShare.appex", "PearlsShare.entitlements", expected_id + ".share"),
            (app, "Pearls-iOS.entitlements", expected_id)]
prepared = []
versions, groups = set(), set()

def require(condition, message):
    if not condition:
        raise SystemExit("Pearls: " + message)

def expand(value, group):
    if isinstance(value, str):
        value = value.replace("$(PEARLS_APP_GROUP)", group)
        require(not re.search(r"\$[({]", value), "Unresolved source entitlement variable: " + value)
        return value
    if isinstance(value, list):
        return [expand(item, group) for item in value]
    if isinstance(value, dict):
        return {key: expand(item, group) for key, item in value.items()}
    return value

# Validate both products and their complete entitlement dictionaries before
# signing either product. All source capability keys are retained.
for product, source, bundle_id in products:
    info = plistlib.loads((product / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == bundle_id, "Unexpected bundle identifier in " + product.name)
    require(info.get("CFBundleVersion") == build, "Unexpected build number in " + product.name)
    require(info.get("DTPlatformName") == "iphoneos", "Archive must contain iPhone device products.")
    version = info.get("CFBundleShortVersionString")
    require(isinstance(version, str) and bool(version.strip()), "Missing marketing version.")
    versions.add(version)
    group = info.get("PearlsAppGroup")
    require(isinstance(group, str) and group.startswith("group.") and len(group) > 6
            and not re.search(r"\s|\$[({]", group), "Missing or unresolved PearlsAppGroup in " + product.name)
    groups.add(group)
    entitlements = expand(plistlib.loads((root / "Configuration" / source).read_bytes()), group)
    require(isinstance(entitlements, dict), "Source entitlements must be a dictionary.")
    app_groups = entitlements.get("com.apple.security.application-groups")
    require(isinstance(app_groups, list) and group in app_groups
            and all(isinstance(item, str) and item.startswith("group.") and len(item) > 6 for item in app_groups),
            "Source App Group entitlement does not match " + product.name)
    for key, wanted in {"application-identifier": team + "." + bundle_id,
                        "com.apple.developer.team-identifier": team, "get-task-allow": False}.items():
        require(key not in entitlements or entitlements[key] == wanted,
                "Source signing entitlement conflicts with TestFlight: " + key)
        entitlements[key] = wanted
    prepared.append((product, entitlements))
require(len(versions) == 1, "App and extension marketing versions differ.")
require(len(groups) == 1, "App and extension PearlsAppGroup values differ.")
with tempfile.TemporaryDirectory(prefix="pearls-entitlements-") as temporary:
    for index, (product, entitlements) in enumerate(prepared):
        path = Path(temporary) / (str(index) + ".plist")
        path.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--entitlements", str(path), str(product)], check=True)
subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
PY

mkdir "$EXPORT_PATH"
EXPORT_OPTIONS="$EXPORT_PATH/ExportOptions.plist"
python3 - "$EXPORT_OPTIONS" "$TEAM_ID" <<'PY'
import plistlib
import sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({
    "method": "app-store-connect", "destination": "export", "teamID": sys.argv[2],
    "signingStyle": "automatic", "manageAppVersionAndBuildNumber": False,
}))
PY
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" "${APPLE_AUTH_ARGS[@]}"
TEAM_ID="$TEAM_ID" BUILD_NUMBER="$BUILD_NUMBER" EXPECTED_IOS_BUNDLE_ID="$EXPECTED_IOS_BUNDLE_ID" \
  bash "$SCRIPT_DIR/verify-testflight.sh" "$EXPORT_PATH"
python3 "$SCRIPT_DIR/package-release.py" finish --record "$SOURCE_RECORD_DIR/source.json" \
  --archive "$ARCHIVE_PATH" --export "$EXPORT_PATH"
printf '\nTestFlight export verified locally: %s\nArchive to upload: %s\nNo upload or invitation was performed.\n' "$EXPORT_PATH" "$ARCHIVE_PATH"
