#!/bin/bash
# Builds HotkeyShow.app from the Swift package.
# Usage: ./scripts/build-app.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/HotkeyShow.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/HotkeyShow" "$APP/Contents/MacOS/HotkeyShow"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough for a locally built menu bar app, and a stable
# identity for the bundle so permissions survive rebuilds at the same path.
if ! codesign --force --sign - "$APP" >/dev/null 2>&1; then
    echo "warning: ad-hoc codesign failed; the app will still run locally" >&2
fi

echo "built $APP"
