# Install

## Platform support

| Platform | Status                                                         | Path                              |
|----------|----------------------------------------------------------------|-----------------------------------|
| macOS    | **Supported** (13+, primary target)                            | Homebrew, install script, source  |
| Windows  | **Beta** — input/screenshot/apps shipped; UIA tree pending     | PowerShell install script, source |
| Linux    | **Roadmap** — AT-SPI2 adapter                                  | not installable yet               |

The macOS path remains the primary target per [`goal.md`](goal.md). Windows ships a day-1 surface (Win32 SendInput, GDI BitBlt/PrintWindow, EnumWindows); UIA-backed tree/observe/find/click-by-selector and WinRT OCR are tracked under the [`windows`](https://github.com/edihasaj/guiport/issues?q=label%3Awindows) label and throw clear `uia_pending` / `ocr_pending` errors today.

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

## Windows (beta)

Windows 10+ on x64. The installer clones the repo and builds via `swift build -c release`, so you need a Swift toolchain on PATH first — install from [swift.org/install/windows](https://www.swift.org/install/windows/).

```powershell
iwr -useb https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.ps1 | iex
```

The script installs to `%LOCALAPPDATA%\Programs\guiport\guiport.exe` and adds that folder to your user PATH. Override with `$env:GUIPORT_INSTALL_DIR` before running.

### Build from source

```powershell
git clone https://github.com/edihasaj/guiport.git
cd guiport
swift build -c release
Copy-Item .\.build\release\guiport.exe "$env:LOCALAPPDATA\Programs\guiport\guiport.exe"
```

### What works today

- `guiport apps` — top-level windows + owning processes (EnumWindows + QueryFullProcessImageNameW).
- `guiport click-at <x> <y>` — SendInput mouse, virtual-desktop coordinates.
- `guiport type "..."` — SendInput keyboard with Unicode injection (handles BMP + surrogate pairs).
- `guiport hotkey ctrl+s` — modifier-aware SendInput sequence; layout-aware via `VkKeyScanW`.
- `guiport screenshot [--app "..."]` — GDI BitBlt for the virtual desktop, PrintWindow for a specific window. Output is BMP today (PNG via WIC pending).

### What's pending

`tree`, `observe`, `find`, `click <selector>`, `find-text`, `record` — these throw `uia_pending` (UIA backend) or `ocr_pending` (Windows.Media.Ocr backend) until COM/WinRT bindings land. Use `click-at` against known coordinates or pair with screenshot diffing in the meantime.

### UIPI / elevated targets

Windows blocks synthetic input from a non-elevated process into elevated windows (e.g. an admin PowerShell). If `SendInput` returns 0, run guiport elevated to match the target.

## Uninstall

```sh
rm -f /usr/local/bin/guiport            # if installed via script/source
brew uninstall guiport                  # if installed via Homebrew
brew untap edihasaj/guiport             # remove the tap
```
