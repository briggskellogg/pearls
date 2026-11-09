#!/bin/bash
# Build a signed iPhone archive. This does not upload or invite testers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_submission_xcode
[ -f "$PEARLS_ROOT/BuildSupport/prepare-assets.sh" ] || fail 'Missing BuildSupport/prepare-assets.sh.'
bash "$PEARLS_ROOT/BuildSupport/prepare-assets.sh"
require_team
load_apple_auth
[[ "${BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]] || fail 'Set BUILD_NUMBER to a positive integer not previously uploaded for this app version (for example, 1 for the first upload).'
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/ios/Pearls-build-$BUILD_NUMBER.xcarchive}"
IOS_DERIVED_DATA="${IOS_DERIVED_DATA:-$BUILD_ROOT/ios-derived}"
case "$IOS_DERIVED_DATA" in /*) ;; *) fail 'IOS_DERIVED_DATA must be an absolute path.' ;; esac
case "$ARCHIVE_PATH" in /*.xcarchive) ;; *) fail 'ARCHIVE_PATH must be an absolute path ending in .xcarchive.' ;; esac
[ ! -e "$ARCHIVE_PATH" ] || fail "Archive already exists: $ARCHIVE_PATH. It was not overwritten. Choose a new BUILD_NUMBER or ARCHIVE_PATH."
mkdir -p "$(dirname "$ARCHIVE_PATH")"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$IOS_SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$IOS_DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  "${APPLE_AUTH_ARGS[@]}" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

APP_INFO="$ARCHIVE_PATH/Products/Applications/Pearls.app/Info.plist"
[ -f "$APP_INFO" ] || fail "The archive does not contain Products/Applications/Pearls.app. Inspect $ARCHIVE_PATH before proceeding."
ACTUAL_BUILD="$(plist_value "$APP_INFO" :CFBundleVersion)" || fail 'Archive has no readable build number.'
[ "$ACTUAL_BUILD" = "$BUILD_NUMBER" ] || fail "Archived build $ACTUAL_BUILD does not match requested build $BUILD_NUMBER. Do not upload this archive until resolved."
printf '\nArchive ready: %s\nBundle: %s\nBuild: %s\n' "$ARCHIVE_PATH" "$(plist_value "$APP_INFO" :CFBundleIdentifier)" "$ACTUAL_BUILD"
printf 'Next, upload this exact archive with scripts/upload-testflight.sh "%s"\n' "$ARCHIVE_PATH"
