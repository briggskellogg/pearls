#!/bin/bash
# Run on the Mac where Pearls should be installed.
set -euo pipefail
PEARLS_PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$(uname -s)" != Darwin ]; then
  printf '%s\n' 'Pearls needs a Mac with Xcode to build and install. No installation was attempted.' >&2
  exit 1
fi
if [ -d /Applications ] && [ -w /Applications ]; then
  bash "$PEARLS_PROJECT_DIR/scripts/install-mac.sh" --developer
  open /Applications/Developer/Pearls.app
else
  bash "$PEARLS_PROJECT_DIR/scripts/install-mac.sh" --user
  open "$HOME/Applications/Pearls.app"
fi
