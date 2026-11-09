#!/bin/bash
# Build an ad-hoc signed app for this Mac. No Developer Program membership needed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_macos_xcode
[ -f "$PEARLS_ROOT/BuildSupport/prepare-assets.sh" ] || fail 'Missing BuildSupport/prepare-assets.sh.'
bash "$PEARLS_ROOT/BuildSupport/prepare-assets.sh"
MAC_DERIVED_DATA="${MAC_DERIVED_DATA:-$BUILD_ROOT/mac-derived}"
case "$MAC_DERIVED_DATA" in /*) ;; *) fail 'MAC_DERIVED_DATA must be an absolute path.' ;; esac

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$MAC_SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$MAC_DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_ENTITLEMENTS="$PEARLS_ROOT/Release/Pearls-Local-Mac.entitlements" \
  PEARLS_APP_GROUP= \
  ONLY_ACTIVE_ARCH=YES \
  build

APP_PATH="$MAC_DERIVED_DATA/Build/Products/$CONFIGURATION/Pearls.app"
[ -d "$APP_PATH" ] || fail "Build finished without the expected app at $APP_PATH. Verify the scheme’s product name."
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
printf '\nBuilt for this Mac: %s\n' "$APP_PATH"
