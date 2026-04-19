#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/London Departures Bar.app"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_TAG="${1:-$(git -C "$ROOT_DIR" describe --tags --always --dirty)}"
VERSION="${RELEASE_TAG#v}"
DMG_NAME="London-Departures-Bar-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/build-app.sh"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "London Departures Bar" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
echo "Built $DMG_PATH"
echo "Checksum written to $DMG_PATH.sha256"
