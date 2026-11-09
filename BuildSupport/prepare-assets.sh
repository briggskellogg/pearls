#!/bin/bash
set -euo pipefail
PEARLS_SUPPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PEARLS_ASSET_ROOT="$(cd "$PEARLS_SUPPORT_DIR/.." && pwd)/Pearls/Resources/Assets.xcassets"
PEARLS_SYMBOL_SOURCE="$PEARLS_ASSET_ROOT/PearlsSymbol.imageset/pearls-symbol.png"
PEARLS_MAKER_SOURCE="$PEARLS_ASSET_ROOT/MakerMark.imageset/maker-mark.png"
PEARLS_MAC_CONTENTS="$PEARLS_ASSET_ROOT/AppIcon-Mac.appiconset/Contents.json"
PEARLS_IOS_CONTENTS="$PEARLS_ASSET_ROOT/AppIcon-iOS.appiconset/Contents.json"
PEARLS_ICONS_COMPLETE=1
for PEARLS_ICON_INPUT in "$PEARLS_SYMBOL_SOURCE" "$PEARLS_MAKER_SOURCE" \
  "$PEARLS_SUPPORT_DIR/PrepareIcons.swift" "$PEARLS_SUPPORT_DIR/prepare-assets.sh"; do
  [ -f "$PEARLS_ICON_INPUT" ] || { printf 'Pearls: missing icon input: %s\n' "$PEARLS_ICON_INPUT" >&2; exit 1; }
  for PEARLS_ICON_CONTENTS in "$PEARLS_MAC_CONTENTS" "$PEARLS_IOS_CONTENTS"; do
    [ -f "$PEARLS_ICON_CONTENTS" ] && [ "$PEARLS_ICON_CONTENTS" -nt "$PEARLS_ICON_INPUT" ] || PEARLS_ICONS_COMPLETE=0
  done
done
for PEARLS_ICON_SIZE in 16 32 64 128 256 512 1024; do
  [ -f "$PEARLS_ASSET_ROOT/AppIcon-Mac.appiconset/AppIcon-$PEARLS_ICON_SIZE.png" ] || PEARLS_ICONS_COMPLETE=0
done
for PEARLS_ICON_SIZE in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do
  [ -f "$PEARLS_ASSET_ROOT/AppIcon-iOS.appiconset/AppIcon-$PEARLS_ICON_SIZE.png" ] || PEARLS_ICONS_COMPLETE=0
done
if [ "$PEARLS_ICONS_COMPLETE" -eq 1 ]; then
  exit 0
fi
if [ "$(uname -s)" != Darwin ]; then
  printf '%s\n' 'Pearls: Apple app icon packaging runs on macOS with Xcode. Source artwork remains unchanged.' >&2
  exit 1
fi
env -u SDKROOT -u SDK_NAME -u PLATFORM_NAME xcrun --sdk macosx swift \
  "$PEARLS_SUPPORT_DIR/PrepareIcons.swift" "$PEARLS_SYMBOL_SOURCE" "$PEARLS_MAKER_SOURCE" "$PEARLS_ASSET_ROOT"
