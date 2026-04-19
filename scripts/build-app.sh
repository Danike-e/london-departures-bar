#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/London Departures Bar.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/LondonDeparturesBar"
ICON="$APP_DIR/Contents/Resources/AppIcon.icns"
SOURCE_PLIST="$ROOT_DIR/Packaging/Info.plist"
SOURCE_ICON="$ROOT_DIR/Assets/AppIcon.icns"

cd "$ROOT_DIR"

swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$SOURCE_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$SOURCE_ICON" "$ICON"
cp "$ROOT_DIR/.build/release/LondonDeparturesBar" "$EXECUTABLE"
chmod 755 "$EXECUTABLE"

if [[ ! -f "$ICON" ]]; then
  echo "Missing $ICON. Generate the app icon before packaging." >&2
  exit 1
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "Built $APP_DIR"
