#!/usr/bin/env bash
# shellcheck disable=SC2016
# Credential-free release-pipeline fixtures. Every Apple command is replaced
# with a small logger so these tests can run on a developer Mac or CI runner
# without a certificate, notary account, or network access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/guiport-release-fixtures.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: $*"
  fi
}

MOCK_BIN="$WORK/mock-bin"
LOG="$WORK/commands.log"
mkdir -p "$MOCK_BIN" "$WORK/app/guiport.app" "$WORK/out"

write_mock() {
  local name="$1"
  shift
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    printf '%s\n' "$@"
  } > "$MOCK_BIN/$name"
  chmod +x "$MOCK_BIN/$name"
}

write_mock codesign \
  'printf "codesign %s\n" "$*" >> "$MOCK_LOG"' \
  '[ "${CODESIGN_FAIL:-0}" != 1 ] || exit 1'
write_mock ditto \
  'printf "notary-zip %s\n" "$*" >> "$MOCK_LOG"' \
  'last=""; for value in "$@"; do last="$value"; done; touch "$last"'
write_mock xcrun \
  'printf "xcrun %s\n" "$*" >> "$MOCK_LOG"' \
  'if [ "$1" = "notarytool" ]; then printf "{\"status\":\"${NOTARY_STATUS:-Accepted}\"}\n"; fi'
write_mock spctl \
  'printf "spctl %s\n" "$*" >> "$MOCK_LOG"' \
  '[ "${SPCTL_FAIL:-0}" != 1 ] || exit 1'
write_mock plutil \
  'printf "%s\n" "${NOTARY_STATUS:-Accepted}"'
write_mock plistbuddy \
  'case "$*" in' \
  '  *"Print :CFBundleIdentifier"*) printf "%s\n" "${FIXTURE_BUNDLE_ID:-com.edihasaj.guiport}" ;;' \
  '  *"Print :CFBundleShortVersionString"*) case "$*" in *".guiport-install."*) printf "%s\n" "${FIXTURE_STAGED_VERSION:-1.2.3}" ;; *) printf "%s\n" "${FIXTURE_INSTALLED_VERSION:-1.2.3}" ;; esac ;;' \
  'esac'
write_mock uname \
  'printf "%s\n" "${FIXTURE_UNAME:-Darwin}"'
write_mock git \
  'if [ "$1" = "clone" ]; then /bin/mkdir -p "${!#}"; /bin/cp -R "$FIXTURE_SOURCE"/. "${!#}"; exit 0; fi' \
  'exit 1'
write_mock swift \
  'if [ "$1" = "build" ]; then /bin/mkdir -p .build/release; /usr/bin/printf "#!/bin/sh\nexit 0\n" > .build/release/guiport; /bin/chmod +x .build/release/guiport; exit 0; fi' \
  'exit 1'
write_mock security \
  'case "$1" in' \
  '  create-keychain) last=""; for value in "$@"; do last="$value"; done; touch "$last" ;;' \
  '  delete-keychain) last=""; for value in "$@"; do last="$value"; done; /bin/rm -f "$last" ;;' \
  '  list-keychains) case " $* " in *" -s "*) ;; *) printf "\"/fixture-default.keychain-db\"\n" ;; esac ;;' \
  '  import) [ "${IMPORT_FAIL:-0}" != 1 ] || exit 1 ;;' \
  '  find-identity) printf "  1) ABCDEF \"Developer ID Application: Applifyer, LLC (T8J48M4QVY)\"\n" ;;' \
  'esac'
write_mock base64 \
  'cat >/dev/null' \
  'printf "fixture-p12\n"'
write_mock pgrep \
  '[ "${PGREP_RUNNING:-0}" != 1 ] || { printf "999\n"; exit 0; }' \
  'exit 1'
write_mock lsof \
  'printf "p999\nftxt\nn%s\n" "${FIXTURE_EXECUTABLE_PATH:-}"'
write_mock lsregister \
  'exit 0'
write_mock ln \
  '[ "${LN_FAIL:-0}" != 1 ] || exit 1' \
  'exec /bin/ln "$@"'
write_mock sudo \
  '[ "${SUDO_FAIL:-0}" != 1 ] || exit 1' \
  'exec "$@"'
write_mock mv \
  'source_path="$1"; destination_path="$2"' \
  'case "$source_path:$destination_path" in' \
  '  *.guiport-install.*/guiport.app:*/guiport.app) [ "${MV_FAIL_PROMOTION:-0}" != 1 ] || exit 1 ;;' \
  '  *.guiport-install.*/previous.app:*/guiport.app) [ "${MV_FAIL_RESTORE:-0}" != 1 ] || exit 1 ;;' \
  'esac' \
  '/bin/mv "$@"' \
  'case "$source_path:$destination_path" in' \
  '  */guiport.app:*.guiport-install.*/previous.app) [ "${MV_SIGNAL_AFTER_BACKUP:-0}" != 1 ] || kill -TERM "$PPID" ;;' \
  'esac'

export PATH="$MOCK_BIN:$PATH"
export MOCK_LOG="$LOG"
export PLISTBUDDY="$MOCK_BIN/plistbuddy"
export PLUTIL="$MOCK_BIN/plutil"
export LSREGISTER="$MOCK_BIN/lsregister"
export LSOF="$MOCK_BIN/lsof"
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

BIN="$WORK/guiport"
ICON="$WORK/icon.icns"
PLIST="$WORK/Info.plist"
printf '#!/bin/sh\nprintf "1.2.3\\n"\n' > "$BIN"
chmod +x "$BIN"
: > "$ICON"
: > "$PLIST"

# Missing identities must fail before the destination is created.
missing_out="$WORK/out/missing.app"
expect_failure "$ROOT/scripts/make-app-bundle.sh" \
  --bin "$BIN" --out "$missing_out" --icon "$ICON" --plist "$PLIST"
[ ! -e "$missing_out" ] || fail "missing identity created a destination"
pass "missing distribution identity aborts before destination mutation"

# Paths are exported before import. A failed `security import` still leaves no
# p12 or temporary keychain behind.
signing_temp="$WORK/signing-temp"
signing_env="$WORK/signing.env"
signing_output="$WORK/signing.output"
mkdir -p "$signing_temp"
if RUNNER_TEMP="$signing_temp" GITHUB_ENV="$signing_env" GITHUB_OUTPUT="$signing_output" \
  CERT_P12_BASE64=fixture CERT_PASSWORD=fixture IMPORT_FAIL=1 \
  "$ROOT/scripts/ci-import-signing.sh" >/dev/null 2>&1; then
  fail "certificate import failure unexpectedly succeeded"
fi
grep -F "GUIPORT_SIGNING_KEYCHAIN=$signing_temp/guiport-signing.keychain-db" "$signing_env" >/dev/null ||
  fail "cleanup keychain path was not exported before import"
grep -F "GUIPORT_CERTIFICATE=$signing_temp/guiport-certificate.p12" "$signing_env" >/dev/null ||
  fail "cleanup certificate path was not exported before import"
[ ! -e "$signing_temp/guiport-signing.keychain-db" ] ||
  fail "failed import left a temporary keychain"
[ ! -e "$signing_temp/guiport-certificate.p12" ] ||
  fail "failed import left a certificate file"
pass "failed certificate import cleans its keychain and p12"

# An existing app is never removed or replaced, even when the caller supplies
# a plausible Developer ID label.
existing="$WORK/out/existing.app"
mkdir -p "$existing"
printf 'keep\n' > "$existing/marker"
expect_failure "$ROOT/scripts/make-app-bundle.sh" \
  --bin "$BIN" --out "$existing" --icon "$ICON" --plist "$PLIST" \
  --identity 'Developer ID Application: Applifyer, LLC (T8J48M4QVY)'
[ "$(cat "$existing/marker")" = "keep" ] || fail "existing destination changed"
pass "existing destination is preserved"

# A successful bundle sign must occur before the notary submission and stapling.
signed_out="$WORK/out/signed.app"
"$ROOT/scripts/make-app-bundle.sh" \
  --bin "$BIN" --out "$signed_out" --icon "$ICON" --plist "$PLIST" \
  --identity 'Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  --version 1.2.3
ASC_KEY_ID=fixture ASC_ISSUER_ID=fixture ASC_KEY_P8=fixture \
  "$ROOT/scripts/ci-notarize.sh" --app "$signed_out" --zip "$WORK/out/notary.zip"
sign_line="$(grep -n 'codesign --force' "$LOG" | head -1 | cut -d: -f1)"
submit_line="$(grep -n 'xcrun notarytool submit' "$LOG" | head -1 | cut -d: -f1)"
staple_line="$(grep -n 'xcrun stapler staple' "$LOG" | head -1 | cut -d: -f1)"
[ -n "$sign_line" ] && [ -n "$submit_line" ] && [ -n "$staple_line" ] ||
  fail "missing signing, notary, or staple operation"
[ "$sign_line" -lt "$submit_line" ] && [ "$submit_line" -lt "$staple_line" ] ||
  fail "signing, notarization, and stapling ran out of order"
pass "signing, notarization acceptance, and stapling run in order"

# The notary key inputs are required before the script writes its temporary ZIP.
missing_secret_zip="$WORK/out/missing-notary-secret.zip"
expect_failure "$ROOT/scripts/ci-notarize.sh" \
  --app "$signed_out" --zip "$missing_secret_zip"
[ ! -e "$missing_secret_zip" ] || fail "missing notary secret created a ZIP"
pass "missing notary credentials abort before ZIP creation"

# A non-Accepted ticket never reaches the caller's package action.
rejected_package="$WORK/out/rejected.tar.gz"
if ASC_KEY_ID=fixture ASC_ISSUER_ID=fixture ASC_KEY_P8=fixture NOTARY_STATUS=Invalid \
  "$ROOT/scripts/ci-notarize.sh" --app "$signed_out" --zip "$WORK/out/rejected.zip" &&
  touch "$rejected_package"; then
  fail "non-Accepted notarization continued to packaging"
fi
[ ! -e "$rejected_package" ] || fail "non-Accepted notarization created a package"
pass "non-Accepted notarization blocks packaging"

# Gatekeeper assessment happens after the stapled ticket and before package work.
gatekeeper_package="$WORK/out/gatekeeper.tar.gz"
if ASC_KEY_ID=fixture ASC_ISSUER_ID=fixture ASC_KEY_P8=fixture SPCTL_FAIL=1 \
  "$ROOT/scripts/ci-notarize.sh" --app "$signed_out" --zip "$WORK/out/gatekeeper.zip" &&
  touch "$gatekeeper_package"; then
  fail "Gatekeeper failure continued to packaging"
fi
[ ! -e "$gatekeeper_package" ] || fail "Gatekeeper failure created a package"
pass "ticket or Gatekeeper failure blocks packaging"

# The macOS source installer must leave a working CLI untouched when it cannot
# make a real signed app. Linux's bare-CLI path stays outside this fixture.
prefix="$WORK/prefix"
mkdir -p "$prefix/bin"
printf 'previous\n' > "$prefix/bin/guiport"
if FIXTURE_SOURCE="$ROOT" PREFIX="$prefix" HOME="$WORK/home" \
  "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "macOS source installer accepted an unsigned fallback"
fi
[ "$(cat "$prefix/bin/guiport")" = "previous" ] ||
  fail "macOS source installer replaced the previous CLI"
pass "macOS installer keeps the prior CLI when app signing is unavailable"

# A stopped expected app upgrades through a new private stage. The source
# installer changes its CLI link only after that promotion succeeds.
upgrade_dest="$WORK/upgrade-apps"
upgrade_prefix="$WORK/upgrade-prefix"
old_app="$upgrade_dest/guiport.app"
mkdir -p "$old_app/Contents/MacOS" "$upgrade_prefix/bin"
: > "$old_app/Contents/Info.plist"
printf 'old-app\n' > "$old_app/marker"
printf 'old-cli\n' > "$upgrade_prefix/bin/guiport"
FIXTURE_SOURCE="$ROOT" PREFIX="$upgrade_prefix" HOME="$WORK/upgrade-home" \
  GUIPORT_APP_DEST="$upgrade_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  "$ROOT/scripts/install.sh" >/dev/null
[ -x "$upgrade_dest/guiport.app/Contents/MacOS/guiport" ] ||
  fail "source installer did not promote a staged app"
[ ! -e "$old_app/marker" ] || fail "source installer retained the old app in place"
[ -L "$upgrade_prefix/bin/guiport" ] || fail "source installer did not update CLI after promotion"
upgrade_rollback="$(find "$upgrade_dest" -maxdepth 3 -path '*/previous.app/marker' -print -quit)"
[ -n "$upgrade_rollback" ] || fail "successful upgrade did not retain a rollback app"
pass "source installer upgrades a stopped expected app and retains rollback"

# A signing failure removes only its private stage and leaves both the previous
# app and CLI untouched.
failed_dest="$WORK/failed-apps"
failed_prefix="$WORK/failed-prefix"
failed_app="$failed_dest/guiport.app"
mkdir -p "$failed_app/Contents/MacOS" "$failed_prefix/bin"
: > "$failed_app/Contents/Info.plist"
printf 'old-app\n' > "$failed_app/marker"
printf 'old-cli\n' > "$failed_prefix/bin/guiport"
if FIXTURE_SOURCE="$ROOT" PREFIX="$failed_prefix" HOME="$WORK/failed-home" \
  GUIPORT_APP_DEST="$failed_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  CODESIGN_FAIL=1 "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "signing failure unexpectedly installed a source app"
fi
[ "$(cat "$failed_app/marker")" = "old-app" ] || fail "signing failure changed prior app"
[ "$(cat "$failed_prefix/bin/guiport")" = "old-cli" ] || fail "signing failure changed prior CLI"
[ -z "$(find "$failed_dest" -maxdepth 1 -name '.guiport-install.*' -print -quit)" ] ||
  fail "signing failure retained a private stage"
pass "signing failure keeps the prior app and CLI untouched"

# A running app is not renamed during upgrade, so its executable and its
# existing CLI remain valid until the user stops it deliberately.
running_dest="$WORK/running-apps"
running_prefix="$WORK/running-prefix"
running_app="$running_dest/guiport.app"
mkdir -p "$running_app/Contents/MacOS" "$running_prefix/bin"
: > "$running_app/Contents/Info.plist"
printf '#!/bin/sh\nexit 0\n' > "$running_app/Contents/MacOS/guiport"
chmod +x "$running_app/Contents/MacOS/guiport"
printf 'running-app\n' > "$running_app/marker"
/bin/ln -s "$running_app/Contents/MacOS/guiport" "$running_prefix/bin/guiport"
if FIXTURE_SOURCE="$ROOT" PREFIX="$running_prefix" HOME="$WORK/running-home" \
  GUIPORT_APP_DEST="$running_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  PGREP_RUNNING=1 \
  FIXTURE_EXECUTABLE_PATH="$running_app/Contents/MacOS/guiport" \
  "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "running app was upgraded"
fi
[ "$(cat "$running_app/marker")" = "running-app" ] || fail "running app was moved"
[ -L "$running_prefix/bin/guiport" ] || fail "running CLI symlink changed"
pass "running app through CLI symlink blocks an unsafe upgrade"

# A newer installed app cannot be downgraded by an older local source build.
downgrade_dest="$WORK/downgrade-apps"
downgrade_prefix="$WORK/downgrade-prefix"
downgrade_app="$downgrade_dest/guiport.app"
mkdir -p "$downgrade_app/Contents/MacOS" "$downgrade_prefix/bin"
: > "$downgrade_app/Contents/Info.plist"
printf 'v0.1.74\n' > "$downgrade_app/marker"
printf 'new-cli\n' > "$downgrade_prefix/bin/guiport"
if FIXTURE_SOURCE="$ROOT" PREFIX="$downgrade_prefix" HOME="$WORK/downgrade-home" \
  GUIPORT_APP_DEST="$downgrade_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  FIXTURE_STAGED_VERSION=0.1.72 FIXTURE_INSTALLED_VERSION=0.1.74 \
  "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "source installer downgraded a newer app"
fi
[ "$(cat "$downgrade_app/marker")" = "v0.1.74" ] || fail "downgrade changed installed app"
[ "$(cat "$downgrade_prefix/bin/guiport")" = "new-cli" ] || fail "downgrade changed CLI"
pass "source installer refuses to downgrade a newer app"

# A failed CLI link leaves the old CLI intact and keeps the exact prior app in
# its rollback stage for recovery after a successful child promotion.
link_dest="$WORK/link-failure-apps"
link_prefix="$WORK/link-failure-prefix"
link_app="$link_dest/guiport.app"
mkdir -p "$link_app/Contents/MacOS" "$link_prefix/bin"
: > "$link_app/Contents/Info.plist"
printf 'old-link-app\n' > "$link_app/marker"
printf 'old-link-cli\n' > "$link_prefix/bin/guiport"
if FIXTURE_SOURCE="$ROOT" PREFIX="$link_prefix" HOME="$WORK/link-home" \
  GUIPORT_APP_DEST="$link_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  LN_FAIL=1 "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "link failure unexpectedly completed installation"
fi
[ "$(cat "$link_prefix/bin/guiport")" = "old-link-cli" ] || fail "link failure changed CLI"
link_rollback="$(find "$link_dest" -maxdepth 3 -path '*/previous.app/marker' -print -quit)"
[ -n "$link_rollback" ] || fail "link failure removed the prior app rollback"
pass "link failure retains prior app rollback and CLI"

# A failed promotion restores the known prior app and clears the private stage.
promotion_dest="$WORK/promotion-failure-apps"
promotion_prefix="$WORK/promotion-failure-prefix"
promotion_app="$promotion_dest/guiport.app"
mkdir -p "$promotion_app/Contents/MacOS" "$promotion_prefix/bin"
: > "$promotion_app/Contents/Info.plist"
printf 'promotion-old-app\n' > "$promotion_app/marker"
printf 'promotion-old-cli\n' > "$promotion_prefix/bin/guiport"
if FIXTURE_SOURCE="$ROOT" PREFIX="$promotion_prefix" HOME="$WORK/promotion-home" \
  GUIPORT_APP_DEST="$promotion_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  MV_FAIL_PROMOTION=1 "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "promotion failure unexpectedly completed installation"
fi
[ "$(cat "$promotion_app/marker")" = "promotion-old-app" ] || fail "promotion failure did not restore prior app"
[ "$(cat "$promotion_prefix/bin/guiport")" = "promotion-old-cli" ] || fail "promotion failure changed CLI"
[ -z "$(find "$promotion_dest" -maxdepth 1 -name '.guiport-install.*' -print -quit)" ] ||
  fail "recovered promotion failure retained a stage"
pass "promotion failure restores prior app and CLI"

# If restoration itself fails, the controlled stage remains available instead
# of deleting the only prior app.
restore_dest="$WORK/restore-failure-apps"
restore_prefix="$WORK/restore-failure-prefix"
restore_app="$restore_dest/guiport.app"
mkdir -p "$restore_app/Contents/MacOS" "$restore_prefix/bin"
: > "$restore_app/Contents/Info.plist"
printf 'restore-old-app\n' > "$restore_app/marker"
printf 'restore-old-cli\n' > "$restore_prefix/bin/guiport"
if FIXTURE_SOURCE="$ROOT" PREFIX="$restore_prefix" HOME="$WORK/restore-home" \
  GUIPORT_APP_DEST="$restore_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  MV_FAIL_PROMOTION=1 MV_FAIL_RESTORE=1 "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "restore failure unexpectedly completed installation"
fi
[ "$(cat "$restore_prefix/bin/guiport")" = "restore-old-cli" ] || fail "restore failure changed CLI"
restore_rollback="$(find "$restore_dest" -maxdepth 3 -path '*/previous.app/marker' -print -quit)"
[ -n "$restore_rollback" ] || fail "restore failure deleted the prior app"
pass "restore failure retains the only prior app in its stage"

# A signal after moving the old app but before promotion exits nonzero and uses
# actual APP/PREVIOUS_APP locations to restore the old bundle.
signal_dest="$WORK/signal-apps"
signal_prefix="$WORK/signal-prefix"
signal_app="$signal_dest/guiport.app"
mkdir -p "$signal_app/Contents/MacOS" "$signal_prefix/bin"
: > "$signal_app/Contents/Info.plist"
printf 'signal-old-app\n' > "$signal_app/marker"
printf 'signal-old-cli\n' > "$signal_prefix/bin/guiport"
if FIXTURE_SOURCE="$ROOT" PREFIX="$signal_prefix" HOME="$WORK/signal-home" \
  GUIPORT_APP_DEST="$signal_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  MV_SIGNAL_AFTER_BACKUP=1 "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "interrupted promotion unexpectedly completed installation"
fi
[ "$(cat "$signal_app/marker")" = "signal-old-app" ] || fail "signal did not restore prior app"
[ "$(cat "$signal_prefix/bin/guiport")" = "signal-old-cli" ] || fail "signal changed CLI"
pass "signal during promotion restores prior app and CLI"

# The privileged-link path has the same rollback behavior when sudo declines.
sudo_dest="$WORK/sudo-failure-apps"
sudo_prefix="$WORK/sudo-failure-prefix"
sudo_app="$sudo_dest/guiport.app"
mkdir -p "$sudo_app/Contents/MacOS" "$sudo_prefix/bin"
: > "$sudo_app/Contents/Info.plist"
printf 'sudo-old-app\n' > "$sudo_app/marker"
printf 'sudo-old-cli\n' > "$sudo_prefix/bin/guiport"
chmod 555 "$sudo_prefix/bin"
if FIXTURE_SOURCE="$ROOT" PREFIX="$sudo_prefix" HOME="$WORK/sudo-home" \
  GUIPORT_APP_DEST="$sudo_dest" \
  GUIPORT_SIGNING_IDENTITY='Developer ID Application: Applifyer, LLC (T8J48M4QVY)' \
  SUDO_FAIL=1 "$ROOT/scripts/install.sh" >/dev/null 2>&1; then
  fail "declined sudo unexpectedly completed installation"
fi
chmod 755 "$sudo_prefix/bin"
[ "$(cat "$sudo_prefix/bin/guiport")" = "sudo-old-cli" ] || fail "declined sudo changed CLI"
sudo_rollback="$(find "$sudo_dest" -maxdepth 3 -path '*/previous.app/marker' -print -quit)"
[ -n "$sudo_rollback" ] || fail "declined sudo removed the prior app rollback"
pass "declined sudo retains prior app rollback and CLI"

echo "release identity fixtures passed"
