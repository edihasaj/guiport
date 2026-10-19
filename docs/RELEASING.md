# Releasing

Releases are intentionally started with **Run workflow** for
`.github/workflows/release.yml`, selecting `production` with both `run_native=true` and `publish=true`. You do not hand-edit
`Version.swift` or cut tags manually. Routine pushes and pull requests never
start a hosted macOS release job.

## Flow

When an owner intentionally dispatches the Release workflow from `production`:

1. **bump** job — increments the patch in `Sources/GuiportCore/Version.swift`,
   commits `chore(release): vX.Y.Z`, tags `vX.Y.Z`, pushes the commit to
   `production` and the tag to the repository. Merge the release commit back to
   `main` after publication so the next release starts from the current version.
2. **release** job (same run) — builds the universal macOS binary, wraps it in a
   Developer-ID-signed `guiport.app`, notarizes and staples that exact app,
   validates the ticket and Gatekeeper assessment, then packages
   `guiport-X.Y.Z-macos-universal.tar.gz`. Only then does it publish the GitHub
   release and bump the Homebrew tap (`edihasaj/homebrew-guiport`) to install
   the bundle + symlink `bin/guiport` into it.

So: **Actions → Release → Run workflow → production** with both opt-ins enabled → a new signed release +
`brew upgrade guiport` within minutes. The workflow is also guarded to release
only from `production`; the bot guard prevents loops if its event policy changes later.

## Hosted native CI

Normal `main` pushes and pull requests retain Linux and Windows CI, but skip the
paid macOS lane. The macOS lane runs only for an explicit **Run workflow** invocation
of CI from `production` with **Run the paid macOS build and unit-test lane** enabled. A skipped
lane is not native proof; use the explicit path before promotion or release.

## Required macOS release identity

A bare `swift build` binary is only **ad-hoc** signed: identifier `guiport`, with a
cdhash that changes every build, and — being a bare CLI, not an app bundle — it has
no logo, so the Privacy panes fall back to the generic executable icon. macOS also
attributes the tool's Screen Recording (TCC) request to the **host terminal**, and
any grant is lost on the next `brew upgrade`. The release wraps the binary in a
`guiport.app` and applies a **Developer ID** signature with a stable identifier
(`com.edihasaj.guiport` + team `T8J48M4QVY`), giving guiport its own logo and a
persistent entry under System Settings → Privacy & Security. Homebrew symlinks
`bin/guiport` into the bundle so the running process is bundle-associated.

The release refuses to bump, tag, sign, package, or upload when any mandatory
credential is absent. It never substitutes an ad-hoc signature or a bare CLI.
The resulting app must satisfy the same designated requirement used when
Guiport registers its Login Item: bundle identifier `com.edihasaj.guiport`,
team `T8J48M4QVY`, a Developer ID Application leaf certificate, and the
Developer ID intermediate certificate.

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | `base64 -i DeveloperIDApplication.p12` — a **Developer ID Application** cert exported from Keychain Access *with its private key* |
| `MACOS_CERT_PASSWORD` | the password set when exporting the `.p12` |
| `ASC_KEY_ID` | App Store Connect API key ID used by `notarytool` |
| `ASC_ISSUER_ID` | App Store Connect issuer ID used by `notarytool` |
| `ASC_KEY_P8` | complete contents of that API key’s `.p8` file |

## Background Login Item ownership

`guiport agent install` and `guiport agent restart` write a LaunchAgent that
associates with the signed `guiport.app` only after it verifies the exact running
executable's bundle layout, identifier, and Developer ID team, then registers
that exact bundle with LaunchServices. This lets System Settings identify the
background item as **Guiport** with its bundled icon. A bare build, wrong bundle,
or invalid signature writes the same working LaunchAgent without an app
association; do not add `AssociatedBundleIdentifiers` manually.

### Exporting the cert

```sh
# Keychain Access → My Certificates → "Developer ID Application: Applifyer, LLC"
# → right-click → Export → .p12 (set a password). Then:
base64 -i DeveloperIDApplication.p12 | pbcopy   # paste into MACOS_CERT_P12_BASE64
```

Add both via `gh secret set MACOS_CERT_P12_BASE64 < file` / the repo Settings →
Secrets and variables → Actions.

`scripts/ci-notarize.sh` creates an owner-readable temporary API-key file and a
temporary ZIP of the final signed app. It submits with `notarytool --wait`,
accepts only JSON status `Accepted`, staples the same app, validates the staple,
checks Gatekeeper with `spctl`, and rechecks the full Developer ID requirement.
The temporary key, response, and ZIP are removed on every exit path. The
workflow similarly removes its `.p12` and temporary keychain and restores the
runner keychain search list before upload.

This is a future-release contract. Do not infer that a historical asset was
produced by it from this document alone; verify that release’s attached
evidence separately.

## Bundle assembly (`scripts/make-app-bundle.sh`)

Both the release workflow and the local `scripts/install-macos-app.sh` assemble the
bundle through `scripts/make-app-bundle.sh`, so the packaged and hand-built apps
share one layout: `Contents/MacOS/guiport`, `Contents/Resources/guiport.icns`, and
a `Contents/Info.plist` stamped (from `Resources/Info.plist`) with
`com.edihasaj.guiport` + the release version. It requires an explicit
`Developer ID Application: …` identity, signs with hardened runtime and a
timestamp, and refuses an existing output destination. It does not ad-hoc sign.

`scripts/install-macos-app.sh` is for deliberate source installs. Pass the
Developer ID identity explicitly, for example:

```sh
scripts/install-macos-app.sh \
  --bin .build/release/guiport \
  --identity "Developer ID Application: Applifyer, LLC (T8J48M4QVY)"
```

Without that identity, it leaves the current install intact and explains how to
use Homebrew or a signed release. `scripts/install.sh` has the same macOS rule;
Linux still installs its release CLI normally. For a non-interactive source
install, pass the identity deliberately through
`GUIPORT_SIGNING_IDENTITY`; the install script does not discover or choose one:

```sh
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh |
  GUIPORT_SIGNING_IDENTITY="Developer ID Application: Applifyer, LLC (T8J48M4QVY)" sh
```

The macOS installer builds and verifies a new app in a private destination-local
stage. It promotes only an existing `com.edihasaj.guiport` bundle after its
process has stopped, and refuses a local downgrade. A signing failure removes
that stage and leaves the previous app and CLI link intact. On an upgrade, the
prior app remains in the exact private stage as a rollback copy until the outer
CLI handoff is known to have completed; a running app must be quit before an
upgrade.

## Fixture coverage

Run the credential-free release checks locally:

```sh
bash scripts/test-release-identity.sh
```

They exercise missing credentials/identity, preservation of an existing app,
sign → notary → staple ordering, rejection and Gatekeeper failures stopping
packaging, and the macOS installer’s no-bare-CLI behavior.

## Verifying a release

```sh
brew update && brew upgrade guiport
# which guiport -> bin symlink -> guiport.app/Contents/MacOS/guiport; verify the bundle:
codesign -dv --verbose=4 "$(dirname "$(readlink -f "$(which guiport)")")/../.." 2>&1 | grep -E 'Identifier|Authority|TeamId'
# Expect: Identifier=com.edihasaj.guiport, Authority=Developer ID Application: Applifyer, LLC
guiport doctor --fix      # grant the prompt
guiport doctor            # all green
```
