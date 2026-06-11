# Releasing

Releases are **fully automated** by `.github/workflows/release.yml`. You do not
hand-edit `Version.swift` or cut tags manually.

## Flow

Every push to `main` that is **not** itself a `chore(release):` bump commit:

1. **bump** job — increments the patch in `Sources/GuiportCore/Version.swift`,
   commits `chore(release): vX.Y.Z`, tags `vX.Y.Z`, pushes both to `main`.
2. **release** job (same run) — builds the universal macOS binary, Developer-ID
   signs it (see below), packages `guiport-X.Y.Z-macos-universal.tar.gz`,
   publishes the GitHub release, and bumps the Homebrew tap
   (`edihasaj/homebrew-guiport`).

So: merge to `main` → a new signed release + `brew upgrade guiport` within minutes.
The bot's own bump commit is skipped by an `actor != github-actions[bot]` guard,
so it never loops.

## Code signing (required for a stable Screen Recording identity)

A bare `swift build` binary is only **ad-hoc** signed: identifier `guiport`, with a
cdhash that changes every build. macOS then attributes the tool's Screen Recording
(TCC) request to the **host terminal**, and any grant is lost on the next
`brew upgrade`. A **Developer ID** signature with a stable identifier
(`com.edihasaj.guiport` + team `T8J48M4QVY`) gives guiport its own persistent entry
under System Settings → Privacy & Security → Screen Recording.

The `release` job signs with `--options runtime` when these repo secrets are set
(it skips gracefully — shipping an ad-hoc binary with a CI warning — if they are not):

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
> on `brew install`, so an unnotarized Developer-ID binary runs without a Gatekeeper
> prompt, and the signature alone is what stabilises the TCC identity. Add a
> `notarytool` step if direct (quarantined) downloads need to pass Gatekeeper —
> note a bare executable cannot be stapled (only `.app`/`.dmg`/`.pkg`).

## The `.app` wrapper (local/dev)

`scripts/install-macos-app.sh` builds a signed `guiport.app` (LaunchServices wrapper,
same `com.edihasaj.guiport` id, with `NSScreenCaptureUsageDescription`). Because it is
a real bundle it can show the permission prompt and carries the project icon in the
permission panes. The Homebrew formula installs only the CLI; the wrapper is optional
and shares the CLI's TCC identity.

## Verifying a release

```sh
brew update && brew upgrade guiport
codesign -dv --verbose=4 "$(readlink -f "$(which guiport)")" 2>&1 | grep -E 'Identifier|Authority|TeamId'
# Expect: Identifier=com.edihasaj.guiport, Authority=Developer ID Application: Applifyer, LLC
guiport doctor --fix      # grant the prompt
guiport doctor            # all green
```
