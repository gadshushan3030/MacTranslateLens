#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/MacTranslateLens.app"
EXECUTABLE="$ROOT_DIR/.build/release/MacTranslateLens"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/MacTranslateLens"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacTranslateLens</string>
  <key>CFBundleIdentifier</key>
  <string>com.gadshushan.MacTranslateLens</string>
  <key>CFBundleName</key>
  <string>MacTranslateLens</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS gives the bundle a stable identity and does not flag it
# as damaged. Note: an ad-hoc signature changes on every rebuild, so macOS will
# re-ask for Screen Recording permission after each rebuild (clipboard
# translation needs no permission and is unaffected).
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
