#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/MacTranslateLens.app"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
DMG_PATH="$DIST_DIR/MacTranslateLens.dmg"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/MacTranslateLens.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "MacTranslateLens" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
