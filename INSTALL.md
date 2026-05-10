# Install

## Platform support

| Platform | Status                              | Path                                |
|----------|-------------------------------------|-------------------------------------|
| macOS    | **Supported** (13+, primary target) | Homebrew, install script, source    |
| Linux    | **Roadmap** — AT-SPI2 adapter       | not installable yet                 |
| Windows  | **Roadmap** — UIA adapter           | not installable yet                 |

Linux and Windows are explicit non-goals at MVP per [`goal.md`](goal.md). The macOS path must stabilize first.

## macOS

### Homebrew (recommended)

```sh
brew tap edihasaj/guiport
brew install guiport
```

> The tap repository is `edihasaj/homebrew-guiport`. Until that's published, use the install script or build from source.

### Install script

```sh
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh
```

The script installs Xcode CLT if missing, builds release, and copies the binary to `/usr/local/bin/guiport`.

### Build from source

```sh
git clone https://github.com/edihasaj/guiport.git
cd guiport
swift build -c release
sudo cp .build/release/guiport /usr/local/bin/guiport
```

### Permissions

guiport needs two macOS permissions:

1. **System Settings → Privacy & Security → Accessibility** — add your terminal.
2. **System Settings → Privacy & Security → Screen Recording** — add your terminal.

Verify:

```sh
guiport doctor
```

## Linux (not yet supported)

```sh
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh
```

The script will exit with a roadmap message. Track the AT-SPI2 adapter via the [`linux`](https://github.com/edihasaj/guiport/issues?q=label%3Alinux) label.

## Windows (not yet supported)

```powershell
iwr -useb https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.ps1 | iex
```

The script will exit with a roadmap message. Track the UIA adapter via the [`windows`](https://github.com/edihasaj/guiport/issues?q=label%3Awindows) label.

## Uninstall

```sh
rm -f /usr/local/bin/guiport            # if installed via script/source
brew uninstall guiport                  # if installed via Homebrew
brew untap edihasaj/guiport             # remove the tap
```
