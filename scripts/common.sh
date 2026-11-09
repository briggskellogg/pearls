#!/bin/bash
# Shared release helpers. No Apple credentials are stored in this repository.
set -euo pipefail

PEARLS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEARLS_ROOT="$(cd "$PEARLS_SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$PEARLS_ROOT/Pearls.xcodeproj}"
MAC_SCHEME="${MAC_SCHEME:-Pearls-Mac}"
IOS_SCHEME="${IOS_SCHEME:-Pearls-iOS}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_ROOT="${BUILD_ROOT:-$PEARLS_ROOT/build}"

fail() { printf 'Pearls: %s\n' "$*" >&2; exit 1; }

require_macos_xcode() {
  [ "$(uname -s)" = Darwin ] || fail 'Native Apple builds require a Mac with full Xcode. This environment is not macOS; no build, installation, or upload was attempted.'
  command -v xcodebuild >/dev/null 2>&1 || fail 'xcodebuild is unavailable. Install full Xcode, open it once to finish setup, then select its developer directory.'
  local selected
  selected="$(xcode-select -p 2>/dev/null)" || fail 'No active developer directory is selected. Set DEVELOPER_DIR to your full Xcode Contents/Developer path.'
  [ -d "$selected" ] || fail 'The selected Xcode developer directory does not exist.'
  xcodebuild -version >/dev/null 2>&1 || fail 'Full Xcode is not ready. Open Xcode to finish setup and accept its license. Command Line Tools alone cannot build these apps.'
  [ -d "$PROJECT_PATH" ] || fail "Project not found: $PROJECT_PATH. Set PROJECT_PATH to Pearls.xcodeproj."
  case "$BUILD_ROOT" in /*) ;; *) fail 'BUILD_ROOT must be an absolute path.' ;; esac
}

require_submission_xcode() {
  require_macos_xcode
  local xcode_major
  xcode_major="$(xcodebuild -version | awk '/^Xcode / { split($2, v, "."); print v[1]; exit }')"
  [[ "$xcode_major" =~ ^[0-9]+$ ]] || fail 'Could not determine the selected Xcode version.'
  [ "$xcode_major" -ge 26 ] || fail 'This TestFlight release script requires Xcode 26 or later, matching Apple’s current iOS build submission requirement. Select a current Xcode installation with DEVELOPER_DIR.'
}

require_team() {
  [[ "${TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || fail 'Set TEAM_ID to your actual 10-character Apple Developer Team ID. Do not use the App Store Connect app ID or issuer ID.'
}

# Arrays avoid word splitting and keep the key itself out of the command line.
# API-key mode is explicit and complete. A saved Xcode account is used only when
# the operator deliberately opts into APPLE_AUTH_MODE=xcode-account.
load_apple_auth() {
  APPLE_AUTH_ARGS=(-allowProvisioningUpdates)
  case "${APPLE_AUTH_MODE:-api-key}" in
    api-key)
      [ -n "${ASC_KEY_PATH:-}" ] || fail 'Set ASC_KEY_PATH to a locally stored App Store Connect .p8 key, or explicitly select APPLE_AUTH_MODE=xcode-account.'
      [ -f "$ASC_KEY_PATH" ] && [ -r "$ASC_KEY_PATH" ] || fail 'ASC_KEY_PATH must name a readable local private-key file.'
      [[ "${ASC_KEY_ID:-}" =~ ^[A-Za-z0-9]+$ ]] || fail 'Set ASC_KEY_ID to the identifier of that App Store Connect API key.'
      [[ "${ASC_ISSUER_ID:-}" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]] || fail 'Set ASC_ISSUER_ID to the team API key’s issuer UUID.'
      APPLE_AUTH_ARGS+=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
      ;;
    xcode-account)
      [ -z "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ] || fail 'Choose one authentication method: unset ASC_KEY_PATH, ASC_KEY_ID, and ASC_ISSUER_ID when using xcode-account mode.'
      ;;
    *) fail 'APPLE_AUTH_MODE must be api-key or xcode-account.' ;;
  esac
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print $2" "$1" 2>/dev/null
}
