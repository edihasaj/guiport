#!/usr/bin/env bash
# Build a signed guiport.app wrapper for non-Homebrew installs and print its
# path so the caller can symlink bin/guiport into it.
#
# The bundle layout + signing live in make-app-bundle.sh (shared with the release
# workflow). A source build must name its Developer ID identity deliberately;
# this script never guesses an identity or creates an ad-hoc replacement app.
set -euo pipefail

BIN="${BIN:-$(command -v guiport || true)}"
DEST="${DEST:-/Applications}"
BUNDLE_ID="${BUNDLE_ID:-com.edihasaj.guiport}"
IDENTITY="${IDENTITY:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$ROOT/assets/icon.icns"

usage() {
  cat <<'EOF'
install-macos-app.sh [--bin <path>] [--dest <dir>] [--identity <name>] [--id <bundle-id>]

Defaults:
  --bin       command -v guiport
  --dest      /Applications, falling back to ~/Applications
  --identity  required Developer ID Application identity, for example
              "Developer ID Application: Applifyer, LLC (T8J48M4QVY)"
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
[ -n "$IDENTITY" ] || {
  echo "a Developer ID Application --identity is required for source installs; use Homebrew or a signed release if you do not have one" >&2
  exit 1
}
case "$IDENTITY" in
  "Developer ID Application: "*) ;;
  *)
    echo "--identity must name a Developer ID Application identity" >&2
    exit 1
    ;;
esac
[ "$BUNDLE_ID" = "com.edihasaj.guiport" ] || {
  echo "source installs must use bundle id com.edihasaj.guiport" >&2
  exit 1
}

APP="$DEST/guiport.app"
if ! mkdir -p "$DEST" 2>/dev/null || [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  APP="$DEST/guiport.app"
  mkdir -p "$DEST"
  echo "note: default dest not writable; using $APP" >&2
fi

PB="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"
LSOF="${LSOF:-/usr/sbin/lsof}"
STAGE="$(mktemp -d "$DEST/.guiport-install.XXXXXX")"
STAGE_APP="$STAGE/guiport.app"
PREVIOUS_APP="$STAGE/previous.app"

cleanup_stage() {
  status=$?
  trap - EXIT HUP INT TERM

  # Reconcile actual locations, rather than a flag: an interruption can occur
  # between renaming the old app and the next shell instruction. Never replace
  # whatever now occupies APP; retain the exact prior app for manual recovery.
  if [ -e "$PREVIOUS_APP" ]; then
    if [ "$status" -ne 0 ] && [ ! -e "$APP" ]; then
      if ! mv "$PREVIOUS_APP" "$APP"; then
        echo "could not restore the previous Guiport app; recovery copy retained: $PREVIOUS_APP" >&2
        exit "$status"
      fi
      rm -rf "$STAGE"
      exit "$status"
    fi

    # A completed child promotion still has to wait for the parent to update
    # bin/guiport. Keep the prior bundle if that handoff later fails, and also
    # retain it after an ambiguous interruption or unexpected final app.
    echo "rollback app: $PREVIOUS_APP" >&2
    exit "$status"
  fi

  rm -rf "$STAGE"
  exit "$status"
}
trap cleanup_stage EXIT
trap 'exit 1' HUP INT TERM

"$ROOT/scripts/make-app-bundle.sh" \
  --bin "$BIN" \
  --out "$STAGE_APP" \
  --icon "$ICON" \
  --identity "$IDENTITY" \
  --id "$BUNDLE_ID"

[ -x "$STAGE_APP/Contents/MacOS/guiport" ] || {
  echo "staged app is missing its guiport executable" >&2
  exit 1
}

version_less_than() {
  awk -v candidate="$1" -v installed="$2" '
    BEGIN {
      count = split(candidate, c, ".")
      installedCount = split(installed, i, ".")
      if (count != 3 || installedCount != 3) exit 2
      for (part = 1; part <= 3; part++) {
        if (c[part] !~ /^[0-9]+$/ || i[part] !~ /^[0-9]+$/) exit 2
        if ((c[part] + 0) < (i[part] + 0)) exit 0
        if ((c[part] + 0) > (i[part] + 0)) exit 1
      }
      exit 1
    }
  '
}

is_running_from_app() {
  local pid executable
  while IFS= read -r pid; do
    # `ps` reports argv[0], which can be Homebrew's bin/guiport symlink. lsof's
    # `txt` mapping reports the executable image instead, so compare that exact
    # path without putting a user-controlled destination into a regex.
    executable="$("$LSOF" -a -p "$pid" -d txt -Fn 2>/dev/null |
      awk 'substr($0, 1, 1) == "n" { print substr($0, 2); exit }')"
    [ "$executable" = "$APP/Contents/MacOS/guiport" ] && return 0
  done < <(pgrep -x guiport 2>/dev/null || true)
  return 1
}

if [ -e "$APP" ]; then
  [ ! -L "$APP" ] && [ -d "$APP" ] || {
    echo "refusing to replace unexpected destination: $APP" >&2
    exit 1
  }
  existing_id="$("$PB" -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  [ "$existing_id" = "$BUNDLE_ID" ] || {
    echo "refusing to replace non-Guiport app at $APP" >&2
    exit 1
  }
  staged_version="$("$PB" -c 'Print :CFBundleShortVersionString' "$STAGE_APP/Contents/Info.plist" 2>/dev/null || true)"
  existing_version="$("$PB" -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
  if version_less_than "$staged_version" "$existing_version"; then
    echo "refusing to downgrade Guiport from $existing_version to $staged_version" >&2
    exit 1
  elif [ "$?" -eq 2 ]; then
    echo "could not compare staged and installed Guiport versions" >&2
    exit 1
  fi
  if is_running_from_app; then
    echo "Guiport is running from $APP; quit it before upgrading" >&2
    exit 1
  fi
  mv "$APP" "$PREVIOUS_APP"
fi

[ ! -e "$APP" ] || {
  echo "destination appeared during promotion; previous app is retained for recovery" >&2
  exit 1
}
mv "$STAGE_APP" "$APP" || {
  echo "could not promote staged Guiport app" >&2
  exit 1
}

lsregister="${LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
[ -x "$lsregister" ] && "$lsregister" -f "$APP" || true
touch "$APP" || true

echo "installed app: $APP"
echo "bundle id: $BUNDLE_ID"
echo "run guiport from inside it: $APP/Contents/MacOS/guiport"
