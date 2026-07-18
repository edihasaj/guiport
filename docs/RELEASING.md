# Releasing

Releases are **fully automated** by `.github/workflows/release.yml`. You do not
hand-edit `Version.swift` or cut tags manually.

## Flow

Every push to `main` that is **not** itself a `chore(release):` bump commit:

1. **bump** job — increments the patch in `Sources/GuiportCore/Version.swift`,
   commits `chore(release): vX.Y.Z`, tags `vX.Y.Z`, pushes both to `main`.
2. **release** job (same run) — builds the universal macOS binary, wraps it in a
   Developer-ID-signed `guiport.app` (via `scripts/make-app-bundle.sh`, see
   below), packages `guiport-X.Y.Z-macos-universal.tar.gz` (containing the
   `.app`), publishes the GitHub release, and bumps the Homebrew tap
   (`edihasaj/homebrew-guiport`) to install the bundle + symlink `bin/guiport`
   into it.

So: merge to `main` → a new signed release + `brew upgrade guiport` within minutes.
The bot's own bump commit is skipped by an `actor != github-actions[bot]` guard,
so it never loops.

## Code signing (required for a stable Screen Recording identity)

A bare `swift build` binary is only **ad-hoc** signed: identifier `guiport`, with a
cdhash that changes every build, and — being a bare CLI, not an app bundle — it has
no logo, so the Privacy panes fall back to the generic executable icon. macOS also
attributes the tool's Screen Recording (TCC) request to the **host terminal**, and
any grant is lost on the next `brew upgrade`. The release wraps the binary in a
`guiport.app` and applies a **Developer ID** signature with a stable identifier
(`com.edihasaj.guiport` + team `T8J48M4QVY`), giving guiport its own logo and a
persistent entry under System Settings → Privacy & Security. Homebrew symlinks
`bin/guiport` into the bundle so the running process is bundle-associated.

The `release` job signs the `.app` with `--options runtime` when these repo secrets
are set (it skips gracefully — shipping an ad-hoc-signed bundle with a CI warning —
if they are not):

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | `base64 -i DeveloperIDApplication.p12` — a **Developer ID Application** cert exported from Keychain Access *with its private key* |
| `MACOS_CERT_PASSWORD` | the password set when exporting the `.p12` |

### Exporting the cert

```sh
# Keychain Access → My Certificates → "Developer ID Application: Applifyer, LLC"
# → right-click → Export → .p12 (set a password). Then:
base64 -i DeveloperIDApplication.p12 | pbcopy   # paste into MACOS_CERT_P12_BASE64
```

Add both via `gh secret set MACOS_CERT_P12_BASE64 < file` / the repo Settings →
Secrets and variables → Actions.

> Notarization is **not** currently performed. Homebrew strips the quarantine bit
> on `brew install`, so an unnotarized Developer-ID bundle runs without a Gatekeeper
> prompt, and the signature alone is what stabilises the TCC identity. The release
> now ships a `.app` (not a bare executable), so it *can* be stapled — add a
> `notarytool submit --wait` + `stapler staple` step if direct (quarantined)
> downloads need to pass Gatekeeper.

## Bundle assembly (`scripts/make-app-bundle.sh`)

Both the release workflow and the local `scripts/install-macos-app.sh` assemble the
bundle through `scripts/make-app-bundle.sh`, so the packaged and hand-built apps
share one layout: `Contents/MacOS/guiport`, `Contents/Resources/guiport.icns`, and
a `Contents/Info.plist` stamped (from `Resources/Info.plist`) with
`com.edihasaj.guiport` + the release version. It signs Developer-ID (hardened
runtime + timestamp) when given an identity, else ad-hoc with the stable identifier.

`scripts/install-macos-app.sh` is for non-Homebrew installs: it picks a signing
identity + a writable install dir, builds the `.app`, and prints its path so the
caller can symlink `bin/guiport` into it (the install script does exactly that).

## Verifying a release

```sh
brew update && brew upgrade guiport
# which guiport -> bin symlink -> guiport.app/Contents/MacOS/guiport; verify the bundle:
codesign -dv --verbose=4 "$(dirname "$(readlink -f "$(which guiport)")")/../.." 2>&1 | grep -E 'Identifier|Authority|TeamId'
# Expect: Identifier=com.edihasaj.guiport, Authority=Developer ID Application: Applifyer, LLC
guiport doctor --fix      # grant the prompt
guiport doctor            # all green
```
