#!/usr/bin/env bash
# Assemble (and sign) a guiport.app bundle around an already-built CLI binary.
#
# Why a bundle: a bare CLI binary has no app identity, so macOS shows the generic
# executable icon in the Privacy & Security panes and keys the TCC grant to a
# per-build ad-hoc identity (lost on every upgrade). Wrapping the binary in a
# real .app — signed with a stable Developer ID — gives guiport its own logo and
# a persistent TCC subject. Installers symlink bin/guiport into
# Contents/MacOS/guiport so the process that actually runs is bundle-associated.
#
# Single source of truth for bundle layout: the release workflow and the local
# install-macos-app.sh both call this, so the packaged and hand-built apps match.
set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.edihasaj.guiport}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BIN=""
ICON="${ICON:-$ROOT/assets/icon.icns}"
PLIST="${PLIST:-$ROOT/Resources/Info.plist}"
OUT=""
IDENTITY="${IDENTITY:-}"
VERSION="${VERSION:-}"

usage() {
  cat <<'EOF'
make-app-bundle.sh --bin <path> --out <guiport.app> [options]

Assembles a signed guiport.app around the given CLI binary.

Required:
  --bin <path>        built guiport executable to embed
  --out <path>        destination .app path (e.g. dist/guiport.app)

Options:
  --icon <path>       .icns icon        (default: assets/icon.icns)
  --plist <path>      Info.plist source (default: Resources/Info.plist)
  --identity <id>     codesign identity (default: "-" ad-hoc). Pass a
                      "Developer ID Application: …" identity for a stable,
                      upgrade-surviving TCC grant.
  --id <bundle-id>    bundle identifier (default: com.edihasaj.guiport)
  --version <x.y.z>   CFBundle version   (default: `<bin> --version`)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --icon) ICON="$2"; shift 2 ;;
    --plist) PLIST="$2"; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --id) BUNDLE_ID="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$BIN" ] && [ -f "$BIN" ] || { echo "missing --bin (built guiport binary)" >&2; exit 1; }
[ -n "$OUT" ] || { echo "missing --out (destination .app path)" >&2; exit 1; }
[ -f "$ICON" ] || { echo "missing icon: $ICON" >&2; exit 1; }
[ -f "$PLIST" ] || { echo "missing Info.plist: $PLIST" >&2; exit 1; }

if [ -z "$VERSION" ]; then
  VERSION="$("$BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 0.0.0)"
fi

PB=/usr/libexec/PlistBuddy
APP="$OUT"

# Rebuild from scratch so a stale bundle can't leak an old binary/icon/signature.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/guiport"
chmod 755 "$APP/Contents/MacOS/guiport"
cp "$ICON" "$APP/Contents/Resources/guiport.icns"

# Start from the checked-in Info.plist (usage strings, LSUIElement) and stamp the
# identity + version so Get Info / the permission panes report the real release.
cp "$PLIST" "$APP/Contents/Info.plist"
plist_set() {
  $PB -c "Set :$1 $2" "$APP/Contents/Info.plist" 2>/dev/null \
    || $PB -c "Add :$1 $3 $2" "$APP/Contents/Info.plist"
}
plist_set CFBundleIdentifier "$BUNDLE_ID" string
plist_set CFBundleExecutable guiport string
plist_set CFBundleIconFile guiport string
plist_set CFBundleShortVersionString "$VERSION" string
plist_set CFBundleVersion "$VERSION" string
plist_set LSMinimumSystemVersion 13.0 string

# Sign: Developer ID (hardened runtime + timestamp) when an identity is given,
# else ad-hoc with the stable identifier so entries at least group by name.
if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
  codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo "built: $APP  (id=$BUNDLE_ID version=$VERSION)"
