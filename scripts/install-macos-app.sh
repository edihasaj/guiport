#!/usr/bin/env bash
# Build/sign a LaunchServices app wrapper for guiport.
#
# The CLI binary and app wrapper intentionally use the same bundle id so
# Screen Recording grants apply consistently across direct CLI use and the app.
set -euo pipefail

BIN="${BIN:-$(command -v guiport || true)}"
DEST="${DEST:-/Applications}"
BUNDLE_ID="${BUNDLE_ID:-com.edihasaj.guiport}"
IDENTITY="${IDENTITY:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT/assets/icon.icns"

usage() {
  cat <<'EOF'
install-macos-app.sh [--bin <path>] [--dest <dir>] [--identity <sha1|name>] [--id <bundle-id>]

Defaults:
  --bin       command -v guiport
  --dest      /Applications, falling back to ~/Applications
  --identity  first valid Developer ID Application or Apple Development identity
  --id        com.edihasaj.guiport
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --id) BUNDLE_ID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$BIN" ] && [ -x "$BIN" ] || { echo "guiport binary not found (pass --bin)" >&2; exit 1; }
[ -f "$ICON" ] || { echo "missing icon: $ICON" >&2; exit 1; }

if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -v CSSMERR | grep -iE 'Developer ID Application|Apple Development' | head -1 | awk '{print $2}')"
fi
[ -n "$IDENTITY" ] || { echo "no codesigning identity found (pass --identity <sha1|name>)" >&2; exit 1; }

VERSION="$("$BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 0.0.0)"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --options runtime "$BIN"

APP="$DEST/guiport.app"
if ! mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" 2>/dev/null; then
  DEST="$HOME/Applications"
  APP="$DEST/guiport.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  echo "note: /Applications not writable; using $APP"
fi

cp "$BIN" "$APP/Contents/MacOS/guiport"
cp "$ICON" "$APP/Contents/Resources/guiport.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>guiport</string>
  <key>CFBundleDisplayName</key><string>guiport</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>guiport</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>guiport</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAccessibilityUsageDescription</key><string>guiport reads the macOS Accessibility tree of running apps so coding agents can inspect UI structure, click by selector, and replay tests deterministically.</string>
  <key>NSScreenCaptureUsageDescription</key><string>guiport captures app windows for screenshots and on-device OCR fallback when an app's accessibility tree is sparse.</string>
  <key>NSAppleEventsUsageDescription</key><string>guiport may activate target apps before sending input events so clicks and keystrokes route correctly.</string>
</dict>
</plist>
PLIST

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --options runtime "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true
touch "$APP"

echo "installed app: $APP"
echo "bundle id: $BUNDLE_ID"
echo "icon: $APP/Contents/Resources/guiport.icns"
