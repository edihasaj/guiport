# Install

## Platform support

| Platform | Status                                | Path                                |
|----------|---------------------------------------|-------------------------------------|
| macOS    | **Supported** (13+, primary target)   | Homebrew, install script, source    |
| Linux    | CLI builds; **no AX adapter yet**     | Build from source                   |
| Windows  | CLI builds via Swift; **no UIA yet**  | Build from source                   |

Linux and Windows builds compile the CLI shell but the desktop-control runtime is macOS-only at MVP. Use those builds for development of the Linux/Windows adapters — the goal.md roadmap puts `Windows UIA` and `Linux AT-SPI2` after the macOS path is solid.

## macOS

### Homebrew (recommended)

```sh
brew tap edihasaj/guiport
brew install guiport
```

> The tap repository is `edihasaj/homebrew-guiport`. Until that's published, use one of the methods below.

### Install script

```sh
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh
```

The script detects macOS, installs Xcode CLT if missing, builds, and copies the binary to `/usr/local/bin/guiport`.

### Build from source

```sh
git clone https://github.com/edihasaj/guiport.git
cd guiport
swift build -c release
sudo cp .build/release/guiport /usr/local/bin/guiport
```

Then grant permissions:

1. **System Settings → Privacy & Security → Accessibility** — add your terminal.
2. **System Settings → Privacy & Security → Screen Recording** — add your terminal.

Verify:

```sh
guiport doctor
```

## Linux (CLI build only — no runtime functionality yet)

```sh
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh
```

Or manually:

```sh
# Install Swift: https://www.swift.org/install/linux/
git clone https://github.com/edihasaj/guiport.git
cd guiport
swift build -c release
sudo cp .build/release/guiport /usr/local/bin/guiport
```

`guiport doctor` will report that AT-SPI2 isn't wired up. Track [`#linux-adapter`](https://github.com/edihasaj/guiport/issues?q=label%3Alinux) for progress.

## Windows (CLI build only — no runtime functionality yet)

PowerShell:

```powershell
iwr -useb https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.ps1 | iex
```

Or manually:

```powershell
# Install Swift on Windows: https://www.swift.org/install/windows/
git clone https://github.com/edihasaj/guiport.git
cd guiport
swift build -c release
copy .build\release\guiport.exe %USERPROFILE%\bin\guiport.exe
```

`guiport doctor` will report that UI Automation isn't wired up. Track [`#windows-adapter`](https://github.com/edihasaj/guiport/issues?q=label%3Awindows) for progress.

## Uninstall

```sh
rm -f /usr/local/bin/guiport            # macOS / Linux
del %USERPROFILE%\bin\guiport.exe       # Windows
brew uninstall guiport                  # if installed via Homebrew
```
