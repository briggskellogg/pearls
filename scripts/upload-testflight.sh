#!/bin/bash
# Export/re-sign a specific archive and upload it to App Store Connect.
# A successful upload is not TestFlight processing, approval, or an invitation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
[ "$#" -eq 1 ] || fail 'Usage: scripts/upload-testflight.sh /absolute/path/Pearls-build-N.xcarchive'
require_submission_xcode
require_team
load_apple_auth
ARCHIVE_PATH="$1"
case "$ARCHIVE_PATH" in /*.xcarchive) ;; *) fail 'Pass an absolute .xcarchive path.' ;; esac
[ -d "$ARCHIVE_PATH" ] && [ -f "$ARCHIVE_PATH/Info.plist" ] || fail 'The specified archive does not exist or has no archive Info.plist.'
APP_INFO="$ARCHIVE_PATH/Products/Applications/Pearls.app/Info.plist"
[ -f "$APP_INFO" ] || fail 'The archive does not contain the expected Pearls iOS app.'
BUNDLE_ID="$(plist_value "$APP_INFO" :CFBundleIdentifier)" || fail 'The archive has no bundle identifier.'
BUILD_NUMBER="$(plist_value "$APP_INFO" :CFBundleVersion)" || fail 'The archive has no build number.'
EXPECTED_IOS_BUNDLE_ID="${EXPECTED_IOS_BUNDLE_ID:-com.briggskellogg.pearls}"
[ "$BUNDLE_ID" = "$EXPECTED_IOS_BUNDLE_ID" ] || fail "Archive belongs to $BUNDLE_ID, not expected $EXPECTED_IOS_BUNDLE_ID. Verify the intended app and explicitly set EXPECTED_IOS_BUNDLE_ID for a customized identifier."
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail 'Archived build number must be a positive integer for this release workflow.'
PLATFORM="$(plist_value "$APP_INFO" :DTPlatformName)" || fail 'The archive has no platform metadata.'
[ "$PLATFORM" = iphoneos ] || fail "Expected an iPhone device archive, found $PLATFORM."
# Xcode itself is the authoritative list of export-method identifiers.
XCODE_HELP="$(xcodebuild -help 2>&1)" || fail 'Could not read the selected Xcode export options.'
case "$XCODE_HELP" in *app-store-connect*) ;; *) fail 'This Xcode does not advertise the app-store-connect export method. Select a current full Xcode installation.' ;; esac
unset XCODE_HELP

EXPORT_PARENT="${EXPORT_PARENT:-$BUILD_ROOT/exports}"
case "$EXPORT_PARENT" in /*) ;; *) fail 'EXPORT_PARENT must be an absolute path.' ;; esac
mkdir -p "$EXPORT_PARENT"
EXPORT_PATH="$(mktemp -d "$EXPORT_PARENT/Pearls-upload-build-$BUILD_NUMBER.XXXXXX")"
EXPORT_OPTIONS="$EXPORT_PATH/ExportOptions.plist"
/usr/bin/plutil -create xml1 "$EXPORT_OPTIONS"
/usr/bin/plutil -insert method -string app-store-connect "$EXPORT_OPTIONS"
/usr/bin/plutil -insert destination -string upload "$EXPORT_OPTIONS"
/usr/bin/plutil -insert teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"
/usr/bin/plutil -insert signingStyle -string automatic "$EXPORT_OPTIONS"
/usr/bin/plutil -insert manageAppVersionAndBuildNumber -bool NO "$EXPORT_OPTIONS"
/usr/bin/plutil -insert stripSwiftSymbols -bool YES "$EXPORT_OPTIONS"
/usr/bin/plutil -insert uploadSymbols -bool YES "$EXPORT_OPTIONS"
/usr/bin/plutil -lint "$EXPORT_OPTIONS"

printf 'Uploading bundle %s, build %s, from %s\n' "$BUNDLE_ID" "$BUILD_NUMBER" "$ARCHIVE_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  "${APPLE_AUTH_ARGS[@]}"
printf '\nXcode reported upload success. Check App Store Connect for processing and export-compliance status, then assign the build to the intended TestFlight group.\n'
printf 'Export output retained: %s\nNo tester invitations were sent by this script.\n' "$EXPORT_PATH"
