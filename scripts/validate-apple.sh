#!/bin/bash
# Compile both platform targets and run Foundation tests without Apple secrets.
# These are validation products, not signed App Store distribution artifacts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_macos_xcode
[ -f "$PEARLS_ROOT/BuildSupport/prepare-assets.sh" ] || fail 'Missing BuildSupport/prepare-assets.sh.'
bash "$PEARLS_ROOT/BuildSupport/prepare-assets.sh"
swift test --package-path "$PEARLS_ROOT/Packages/PearlsCore"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$MAC_SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_ROOT/validation-mac" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$IOS_SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$BUILD_ROOT/validation-ios" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
printf '\nCore tests and both platform compile checks completed. TestFlight signing and device behavior require a separate release check.\n'
