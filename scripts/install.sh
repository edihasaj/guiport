#!/usr/bin/env sh
# Installer for guiport (macOS only at MVP).
# Usage:  curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh
set -eu

REPO="https://github.com/edihasaj/guiport.git"
PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="$PREFIX/bin"
WORK_DIR="$(mktemp -d)"

UNAME_S="$(uname -s)"

say()  { printf "[guiport] %s\n" "$*"; }
warn() { printf "[guiport] WARNING: %s\n" "$*" 1>&2; }
die()  { printf "[guiport] ERROR: %s\n" "$*" 1>&2; exit 1; }

case "$UNAME_S" in
  Darwin) ;;
  Linux)
    die "Linux is not supported at MVP. The desktop-control runtime is macOS-only.
       Track the Linux AT-SPI2 adapter on the roadmap (see INSTALL.md)."
    ;;
  *)
    die "Unsupported OS: $UNAME_S. macOS only at MVP. See INSTALL.md."
    ;;
esac

if ! command -v swift >/dev/null 2>&1; then
  say "Swift not found — running 'xcode-select --install' (confirm the GUI prompt)."
  xcode-select --install 2>/dev/null || true
  die "Re-run this installer once Xcode Command Line Tools finish installing."
fi

if ! command -v git >/dev/null 2>&1; then
  die "git not found. Install Xcode Command Line Tools and retry."
fi

say "Cloning $REPO into $WORK_DIR"
git clone --depth 1 "$REPO" "$WORK_DIR/guiport"
cd "$WORK_DIR/guiport"

say "Building (release)…"
swift build -c release

BIN_SRC=".build/release/guiport"
[ -f "$BIN_SRC" ] || die "Build did not produce $BIN_SRC"

say "Installing to $BIN_DIR/guiport (sudo may prompt)…"
if [ -w "$BIN_DIR" ]; then
  cp "$BIN_SRC" "$BIN_DIR/guiport"
else
  sudo cp "$BIN_SRC" "$BIN_DIR/guiport"
fi

say "Cleaning up $WORK_DIR"
rm -rf "$WORK_DIR"

say "Installed: $(command -v guiport)"
say "Next:"
say "  1. Grant Accessibility + Screen Recording in System Settings → Privacy & Security."
say "  2. Add the terminal app you'll run guiport from (Terminal/iTerm/Ghostty/etc.)."
say "  3. Run: guiport doctor"
