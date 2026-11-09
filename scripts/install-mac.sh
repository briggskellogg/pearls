#!/bin/bash
# Install a locally built app, retaining any previous same-identity Pearls app.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
case "${1:---developer}" in
  --developer) INSTALL_DIR=/Applications/Developer ;;
  --user) INSTALL_DIR="$HOME/Applications" ;;
  --system) INSTALL_DIR=/Applications ;;
  --help|-h)
    printf 'Usage: %s [--developer|--user|--system]\nDefault: /Applications/Developer. --developer and --system require writable destination folders. No sudo is used.\n' "$0"
    exit 0 ;;
  *) fail 'Use --developer (default), --user, or --system; see --help.' ;;
esac
[ "$#" -le 1 ] || fail 'Only one install destination option is accepted.'
require_macos_xcode
# An iPhone Simulator process has the same executable name, but cannot hold
# the Mac app open. Keep the guard scoped to native Mac app bundles.
while IFS= read -r PEARLS_PID; do
  PEARLS_EXECUTABLE="$(/bin/ps -p "$PEARLS_PID" -o comm= 2>/dev/null || true)"
  case "$PEARLS_EXECUTABLE" in
    */Pearls.app/Contents/MacOS/Pearls)
      fail 'Pearls is running. Quit the Mac app before installing a new build; no process was stopped.' ;;
  esac
done < <(/usr/bin/pgrep -x Pearls || true)
mkdir -p "$INSTALL_DIR" || fail "Could not create $INSTALL_DIR."
[ -w "$INSTALL_DIR" ] || fail "$INSTALL_DIR is not writable. Use --user or arrange access to the system Applications folder."

"$SCRIPT_DIR/build-mac.sh"
MAC_DERIVED_DATA="${MAC_DERIVED_DATA:-$BUILD_ROOT/mac-derived}"
SOURCE_APP="$MAC_DERIVED_DATA/Build/Products/$CONFIGURATION/Pearls.app"
DESTINATION="$INSTALL_DIR/Pearls.app"
[ ! -L "$DESTINATION" ] || fail "Refusing to replace the symbolic link at $DESTINATION."
NEW_ID="$(plist_value "$SOURCE_APP/Contents/Info.plist" :CFBundleIdentifier)" || fail 'The built app has no bundle identifier.'
[ -n "$NEW_ID" ] || fail 'The built app bundle identifier is empty.'
if [ -e "$DESTINATION" ]; then
  [ -d "$DESTINATION" ] || fail "An unrelated file already exists at $DESTINATION."
  OLD_ID="$(plist_value "$DESTINATION/Contents/Info.plist" :CFBundleIdentifier)" || fail 'The existing Pearls.app has no readable bundle identifier; it was left untouched.'
  [ "$OLD_ID" = "$NEW_ID" ] || fail "The existing Pearls.app has a different bundle identifier ($OLD_ID). It was left untouched."
fi

STAGING="$(mktemp -d "$INSTALL_DIR/.pearls-install.XXXXXX")"
BACKUP=''
MOVED_PREVIOUS=0
cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$MOVED_PREVIOUS" -eq 1 ] && [ ! -e "$DESTINATION" ] && [ -d "$BACKUP" ]; then
    /bin/mv "$BACKUP" "$DESTINATION" || printf 'Previous app remains at %s; restore it manually.\n' "$BACKUP" >&2
  fi
  # STAGING is always the newly created private directory, never an existing app.
  if [ -n "${STAGING:-}" ] && [ -d "$STAGING" ]; then /bin/rm -rf "$STAGING"; fi
  exit "$status"
}
trap cleanup EXIT
/usr/bin/ditto "$SOURCE_APP" "$STAGING/Pearls.app"
/usr/bin/codesign --verify --deep --strict "$STAGING/Pearls.app"
if [ -d "$DESTINATION" ]; then
  BACKUP="$INSTALL_DIR/Pearls-backup-$(date -u +%Y%m%dT%H%M%SZ).app"
  [ ! -e "$BACKUP" ] || fail "Backup path already exists: $BACKUP. Try again after a second."
  /bin/mv "$DESTINATION" "$BACKUP"
  MOVED_PREVIOUS=1
fi
/bin/mv "$STAGING/Pearls.app" "$DESTINATION"
printf '\nInstalled: %s\n' "$DESTINATION"
if [ -n "$BACKUP" ]; then printf 'Previous app retained: %s\n' "$BACKUP"; fi
printf 'Open Pearls from Applications or run: open "%s"\n' "$DESTINATION"
