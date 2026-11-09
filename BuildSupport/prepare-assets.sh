#!/bin/bash
set -euo pipefail
PEARLS_SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEARLS_ASSET_ROOT="$(cd "$PEARLS_SUPPORT_DIR/.." && pwd)/Pearls/Resources/Assets.xcassets"
PEARLS_MARK_SOURCE="$PEARLS_ASSET_ROOT/PearlsMark.imageset/pearls.png"
PEARLS_MAC_CONTENTS="$PEARLS_ASSET_ROOT/AppIcon-Mac.appiconset/Contents.json"
PEARLS_IOS_CONTENTS="$PEARLS_ASSET_ROOT/AppIcon-iOS.appiconset/Contents.json"
PEARLS_ICONS_COMPLETE=1
for PEARLS_ICON_SIZE in 16 32 64 128 256 512 1024; do
  [ -f "$PEARLS_ASSET_ROOT/AppIcon-Mac.appiconset/AppIcon-$PEARLS_ICON_SIZE.png" ] || PEARLS_ICONS_COMPLETE=0
done
for PEARLS_ICON_SIZE in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do
  [ -f "$PEARLS_ASSET_ROOT/AppIcon-iOS.appiconset/AppIcon-$PEARLS_ICON_SIZE.png" ] || PEARLS_ICONS_COMPLETE=0
done
if [ -f "$PEARLS_MAC_CONTENTS" ] && [ -f "$PEARLS_IOS_CONTENTS" ] && \
   [ "$PEARLS_ICONS_COMPLETE" -eq 1 ] && \
   [ "$PEARLS_MAC_CONTENTS" -nt "$PEARLS_MARK_SOURCE" ] && \
   [ "$PEARLS_IOS_CONTENTS" -nt "$PEARLS_MARK_SOURCE" ] && \
   [ "$PEARLS_MAC_CONTENTS" -nt "$PEARLS_SUPPORT_DIR/PrepareIcons.swift" ] && \
   [ "$PEARLS_MAC_CONTENTS" -nt "$PEARLS_SUPPORT_DIR/prepare-assets.sh" ]; then
  exit 0
fi
if [ "$(uname -s)" != Darwin ]; then
  printf '%s\n' 'Pearls: Apple app icon packaging runs on macOS with Xcode. The original mark is included unchanged.' >&2
  exit 1
fi
env -u SDKROOT -u SDK_NAME -u PLATFORM_NAME xcrun --sdk macosx swift \
  "$PEARLS_SUPPORT_DIR/PrepareIcons.swift" "$PEARLS_MARK_SOURCE" "$PEARLS_ASSET_ROOT"
