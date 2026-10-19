#!/usr/bin/env bash
# Import the release Developer ID certificate into a temporary keychain.
#
# The caller supplies GitHub Actions' GITHUB_ENV and GITHUB_OUTPUT paths. The
# cleanup contract is deliberate: paths are published before any fallible
# operation, and this process restores/deletes everything itself on a failed
# import. The workflow's always() cleanup handles the successful path.
set -euo pipefail

RUNNER_TEMP="${RUNNER_TEMP:?RUNNER_TEMP is required}"
GITHUB_ENV="${GITHUB_ENV:?GITHUB_ENV is required}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${CERT_P12_BASE64:?CERT_P12_BASE64 is required}"
: "${CERT_PASSWORD:?CERT_PASSWORD is required}"

keychain="$RUNNER_TEMP/guiport-signing.keychain-db"
certificate="$RUNNER_TEMP/guiport-certificate.p12"
original_keychains="$RUNNER_TEMP/guiport-original-keychains.txt"
complete=0
keychain_created=0
certificate_created=0
search_list_saved=0

die() { echo "ci-import-signing: $*" >&2; exit 1; }

[ ! -e "$keychain" ] || die "temporary keychain path already exists"
[ ! -e "$certificate" ] || die "temporary certificate path already exists"
[ ! -e "$original_keychains" ] || die "temporary keychain-list path already exists"

restore_keychain_search_list() {
  [ -f "$original_keychains" ] || return 0
  local saved=()
  local line
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line#\"}"
    line="${line%\"}"
    [ -n "$line" ] && saved+=("$line")
  done < "$original_keychains"
  [ "${#saved[@]}" -eq 0 ] || security list-keychains -d user -s "${saved[@]}" || true
}

prepend_temporary_keychain() {
  local saved=()
  local line
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line#\"}"
    line="${line%\"}"
    [ -n "$line" ] && saved+=("$line")
  done < "$original_keychains"
  security list-keychains -d user -s "$keychain" "${saved[@]}"
}

cleanup_failed_import() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [ "$complete" -ne 1 ]; then
    [ "$search_list_saved" -ne 0 ] && restore_keychain_search_list
    [ "$certificate_created" -eq 0 ] || rm -f "$certificate"
    rm -f "$original_keychains"
    [ "$keychain_created" -eq 0 ] || security delete-keychain "$keychain" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup_failed_import EXIT HUP INT TERM

# Publish deterministic cleanup locations first. The downstream always() step
# can now clean even if certificate decoding, import, partition setup, or
# identity discovery fails before this script completes.
printf 'GUIPORT_SIGNING_KEYCHAIN=%s\n' "$keychain" >> "$GITHUB_ENV"
printf 'GUIPORT_CERTIFICATE=%s\n' "$certificate" >> "$GITHUB_ENV"

umask 077
keychain_password="$(uuidgen)"
keychain_created=1
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
certificate_created=1
: > "$certificate"
printf '%s' "$CERT_P12_BASE64" | base64 --decode > "$certificate"
security import "$certificate" -k "$keychain" -P "$CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" \
  "$keychain" >/dev/null

security list-keychains -d user > "$original_keychains"
search_list_saved=1
prepend_temporary_keychain

identity="$(security find-identity -p codesigning "$keychain" \
  | grep -oE '"Developer ID Application: [^"]+"' | head -1 | tr -d '"' || true)"
[ -n "$identity" ] || {
  echo "certificate does not contain a Developer ID Application identity" >&2
  exit 1
}
printf 'identity=%s\n' "$identity" >> "$GITHUB_OUTPUT"

complete=1
