#!/usr/bin/env bash
# Build a signed guiport.app wrapper for non-Homebrew installs and print its
# path so the caller can symlink bin/guiport into it.
#
# The bundle layout + signing live in make-app-bundle.sh (shared with the release
# workflow); this script only picks a signing identity and a writable install
# dir, then registers the result with LaunchServices. Running guiport from inside
# the bundle is what gives it the real logo + a stable TCC identity.
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
              (falls back to ad-hoc "-" if none found)
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

if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -v CSSMERR | grep -iE 'Developer ID Application|Apple Development' | head -1 | awk '{print $2}')"
fi
# No real identity: ad-hoc so the bundle is at least signed with a stable id.
[ -n "$IDENTITY" ] || IDENTITY="-"

APP="$DEST/guiport.app"
if ! mkdir -p "$DEST" 2>/dev/null || [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  APP="$DEST/guiport.app"
  mkdir -p "$DEST"
  echo "note: default dest not writable; using $APP" >&2
fi

"$ROOT/scripts/make-app-bundle.sh" \
  --bin "$BIN" \
  --out "$APP" \
  --icon "$ICON" \
  --identity "$IDENTITY" \
  --id "$BUNDLE_ID"

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$lsregister" ] && "$lsregister" -f "$APP" || true
touch "$APP"

echo "installed app: $APP"
echo "bundle id: $BUNDLE_ID"
echo "run guiport from inside it: $APP/Contents/MacOS/guiport"
