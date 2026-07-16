#!/usr/bin/env sh
# Installer for guiport (macOS + Linux beta).
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
    say "Linux beta — day-1 surface (apps, click-at, type, hotkey, screenshot)."
    say "AT-SPI2 tree is pending; see INSTALL.md for status."
    ;;
  *)
    die "Unsupported OS: $UNAME_S. macOS + Linux only. See INSTALL.md."
    ;;
esac

if ! command -v swift >/dev/null 2>&1; then
  if [ "$UNAME_S" = "Darwin" ]; then
    say "Swift not found — running 'xcode-select --install' (confirm the GUI prompt)."
    xcode-select --install 2>/dev/null || true
    die "Re-run this installer once Xcode Command Line Tools finish installing."
  else
    die "Swift not found. Install via swiftly (https://www.swift.org/install/linux/) and retry."
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  die "git not found. Install it (xcode-select / your distro package manager) and retry."
fi

say "Cloning $REPO into $WORK_DIR"
git clone --depth 1 "$REPO" "$WORK_DIR/guiport"
cd "$WORK_DIR/guiport"

say "Building (release)…"
swift build -c release

BIN_SRC=".build/release/guiport"
[ -f "$BIN_SRC" ] || die "Build did not produce $BIN_SRC"

install_bare=0
if [ "$UNAME_S" = "Darwin" ]; then
  say "Building signed guiport.app wrapper…"
  # Install the .app, then point bin/guiport INSIDE it so the running process is
  # bundle-associated (real logo + stable TCC identity), instead of a bare binary.
  app_line="$(scripts/install-macos-app.sh --bin "$BIN_SRC" 2>/dev/null | grep '^installed app: ' || true)"
  app_path="${app_line#installed app: }"
  app_exe="$app_path/Contents/MacOS/guiport"
  if [ -n "$app_path" ] && [ -x "$app_exe" ]; then
    say "Linking $BIN_DIR/guiport → $app_exe (sudo may prompt)…"
    if [ -w "$BIN_DIR" ]; then
      ln -sf "$app_exe" "$BIN_DIR/guiport"
    else
      sudo ln -sf "$app_exe" "$BIN_DIR/guiport"
    fi
    say "guiport runs from inside guiport.app — real logo + stable TCC identity."
  else
    warn "Could not build guiport.app wrapper; installing the bare CLI instead."
    warn "Permission panes may show a generic icon and grants may reset on updates."
    install_bare=1
  fi
else
  install_bare=1
fi

if [ "$install_bare" = "1" ]; then
  say "Installing to $BIN_DIR/guiport (sudo may prompt)…"
  if [ -w "$BIN_DIR" ]; then
    cp "$BIN_SRC" "$BIN_DIR/guiport"
  else
    sudo cp "$BIN_SRC" "$BIN_DIR/guiport"
  fi
fi

say "Cleaning up $WORK_DIR"
rm -rf "$WORK_DIR"

say "Installed: $(command -v guiport)"
case "$UNAME_S" in
  Darwin)
    say "Next:"
    say "  1. Grant Accessibility + Screen Recording to guiport in System Settings → Privacy & Security."
    say "  2. Run: guiport doctor"
    ;;
  Linux)
    say "Next:"
    say "  X11:     install xdotool, wmctrl, scrot (or imagemagick) — apt/dnf/pacman."
    say "  Wayland: install ydotool (+ run ydotoold) and grim."
    say "  Then:    guiport doctor"
    ;;
esac
