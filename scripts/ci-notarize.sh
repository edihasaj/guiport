#!/usr/bin/env bash
# Notarize and validate an already Developer-ID-signed Guiport app.
#
# This produces only a temporary ZIP for Apple's service. The release workflow
# packages the final tarball only after this script returns successfully.
set -euo pipefail

APP=""
ZIP=""
PLUTIL="${PLUTIL:-/usr/bin/plutil}"
REQUIREMENT='anchor apple generic and identifier "com.edihasaj.guiport" and certificate leaf[subject.OU] = "T8J48M4QVY" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate 1[field.1.2.840.113635.100.6.2.6] exists'

usage() {
  cat <<'EOF'
ci-notarize.sh --app <guiport.app> --zip <temporary-notary-input.zip>

Requires ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_P8 in the environment.
EOF
}

die() { echo "ci-notarize: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --zip) ZIP="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$APP" ] && [ -d "$APP" ] || die "missing --app"
[ -n "$ZIP" ] || die "missing --zip"
[ ! -e "$ZIP" ] || die "notary ZIP already exists: $ZIP"
[ -n "${ASC_KEY_ID:-}" ] || die "ASC_KEY_ID is required"
[ -n "${ASC_ISSUER_ID:-}" ] || die "ASC_ISSUER_ID is required"
[ -n "${ASC_KEY_P8:-}" ] || die "ASC_KEY_P8 is required"

zip_parent="$(dirname "$ZIP")"
[ -d "$zip_parent" ] || die "notary ZIP parent does not exist: $zip_parent"

umask 077
key="$(mktemp "${TMPDIR:-/tmp}/guiport-notary-key.XXXXXX")"
receipt="$(mktemp "${TMPDIR:-/tmp}/guiport-notary-receipt.XXXXXX")"
cleanup() {
  rm -f "$key" "$receipt" "$ZIP"
}
trap cleanup EXIT HUP INT TERM

# Validate the exact executable identity before upload. The requirement checks
# the stable bundle ID, Applifyer team, Developer ID Application leaf marker,
# and Developer ID intermediate marker.
codesign --verify --strict --deep --verbose=2 -R="$REQUIREMENT" "$APP"

# ASC_KEY_P8 is written only to an owner-readable temporary file. Avoid echoing
# it, the certificate material, or a command trace.
printf '%s' "$ASC_KEY_P8" > "$key"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
  --key "$key" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait \
  --output-format json > "$receipt"

status="$("$PLUTIL" -extract status raw -o - - < "$receipt")"
[ "$status" = "Accepted" ] || die "notarization did not return Accepted (status: $status)"

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
codesign --verify --strict --deep --verbose=2 -R="$REQUIREMENT" "$APP"

echo "notarized and validated: $APP"
