#!/bin/bash
# package-dmg.sh — packages dist/DSH Web.app into a distributable .dmg installer
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/DSH Web.app"
DMG_NAME="DSH-Web-Desktop-macOS.dmg"
DMG_OUT="$DIST/$DMG_NAME"

[ -d "$APP" ] || { bash "$ROOT/scripts/assemble.sh"; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "preparing DMG staging..."
cp -R "$APP" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

rm -f "$DMG_OUT"
echo "creating DMG: $DMG_OUT..."
hdiutil create -volname "DSH Web Installer" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_OUT"

echo "DMG packaged successfully: $DMG_OUT"
du -sh "$DMG_OUT"
