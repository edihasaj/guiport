# Install

## Platform support

| Platform | Status                                                            | Path                                      |
|----------|-------------------------------------------------------------------|-------------------------------------------|
| macOS    | **Available** (13+, primary target — full stack)                  | Homebrew, install script, source          |
| Windows  | **Available** — input/screenshot/apps; UIA tree pending           | Prebuilt binary (Releases), source        |
| Linux    | **Available** — input/screenshot/apps; AT-SPI2 tree pending       | Prebuilt binary (Releases), install script, source |

Prebuilt binaries for all three platforms are attached to every [release](https://github.com/edihasaj/guiport/releases/latest) — Windows ships with the Swift runtime DLLs bundled and Linux is statically linked (glibc 2.35+), so neither needs a Swift toolchain installed. The macOS path remains the primary target per [`goal.md`](goal.md). Windows ships input/screenshot/apps (Win32 SendInput, GDI BitBlt/PrintWindow → real PNG, EnumWindows); UIA-backed tree/observe/find/click-by-selector and WinRT OCR are tracked under [`windows`](https://github.com/edihasaj/guiport/issues?q=label%3Awindows). Linux ships the same shape via thin wrappers around `xdotool`/`wmctrl`/`scrot` (X11) and `ydotool`/`grim` (Wayland); AT-SPI2 tree + tesseract OCR are tracked under [`linux`](https://github.com/edihasaj/guiport/issues?q=label%3Alinux). All UIA/AT-SPI/OCR-gated calls throw clear `*_pending` errors today instead of silently failing.

## macOS

### Homebrew (recommended)

```sh
brew install edihasaj/guiport/guiport
```

Or tap first, then install:

```sh
brew tap edihasaj/guiport
brew install guiport
```

Ships a universal (arm64 + x86_64) binary from the
[`edihasaj/homebrew-guiport`](https://github.com/edihasaj/homebrew-guiport)
tap; each tagged release auto-bumps the formula, so `brew upgrade guiport`
tracks the latest.

### Install script

```sh
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh
```

The script installs Xcode CLT if missing, builds release, copies the binary to
`/usr/local/bin/guiport`, and installs a signed `guiport.app` wrapper with the
project icon for stable macOS permission grants.

### Build from source

```sh
git clone https://github.com/edihasaj/guiport.git
cd guiport
swift build -c release
sudo cp .build/release/guiport /usr/local/bin/guiport
scripts/install-macos-app.sh --bin /usr/local/bin/guiport
```

### Permissions

guiport needs two macOS permissions:

1. **System Settings → Privacy & Security → Accessibility** — add `guiport`.
2. **System Settings → Privacy & Security → Screen Recording** — add `guiport`.

Run `guiport doctor --fix` to trigger both prompts and have macOS enrol `guiport`
as its own subject (it uses ScreenCaptureKit, so the grant is attributed to
`guiport` itself — not the terminal hosting it), then toggle it ON. It also
registers `~/Applications/guiport.app` so the permission lists show a real app
entry.

> Upgrading from an older build whose Screen Recording grant was attributed to your
> terminal? Reset just guiport's stale entry without touching other apps:
> `tccutil reset ScreenCapture com.edihasaj.guiport`, then `guiport doctor --fix`.

Verify:

```sh
guiport doctor
```

## Linux

X11 or Wayland session. Fastest path — download the prebuilt, statically linked binary (glibc 2.35+, no Swift toolchain needed):

```sh
curl -fsSL https://github.com/edihasaj/guiport/releases/latest/download/guiport-linux-x86_64.tar.gz | tar xz
sudo install guiport /usr/local/bin/guiport
```

> The asset is versioned (`guiport-<ver>-linux-x86_64.tar.gz`); grab the exact name from the [latest release](https://github.com/edihasaj/guiport/releases/latest).

Or build from source — the installer clones the repo and builds via `swift build -c release`, so a Swift toolchain (e.g. via [swiftly](https://www.swift.org/install/linux/)) must be on PATH:

```sh
curl -fsSL https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.sh | sh
```

### Runtime tooling

guiport shells out to standard desktop tools — install whichever your session uses:

**X11**

```sh
sudo apt install xdotool wmctrl scrot imagemagick     # Debian/Ubuntu
sudo dnf install xdotool wmctrl scrot ImageMagick     # Fedora
sudo pacman -S xdotool wmctrl scrot imagemagick       # Arch
```

**Wayland**

```sh
sudo apt install ydotool grim                          # Debian/Ubuntu
sudo dnf install ydotool grim                          # Fedora
sudo pacman -S ydotool grim                            # Arch
sudo systemctl --user enable --now ydotool             # ydotoold needs /dev/uinput access
```

### What works today

- `guiport apps` — `wmctrl -lpG` on X11 (full window list with pids), `/proc` walk on Wayland (no per-window count).
- `guiport click-at <x> <y>` — `xdotool mousemove + click` on X11, `ydotool mousemove --absolute + click` on Wayland.
- `guiport type "..."` — `xdotool type --clearmodifiers --delay <ms> --` / `ydotool type --key-delay <ms> --`.
- `guiport hotkey ctrl+s` — modifier-aware combo translated to xdotool key names (X11) or `KEY_*` evdev names (Wayland).
- `guiport screenshot [--app "..."]` — full-screen via scrot/import/grim/gnome-screenshot in priority order; per-window via `import -window <id>` on X11.

### What's pending

`tree`, `observe`, `find`, `click <selector>`, `find-text`, `record`, and per-window screenshots on Wayland — these throw `atspi_pending` (AT-SPI2 D-Bus tree) / `ocr_pending` (tesseract) / `recorder_pending` (evdev/libei) / `wayland_per_window_unsupported` until those backends land. Use `click-at` against known coordinates plus screenshot diffing in the meantime.

### `ydotool` notes

`ydotool` requires the `ydotoold` daemon running with access to `/dev/uinput`. If `SendInput`-style calls fail with "input_failed", confirm the daemon is up (`systemctl --user status ydotool`) and that your user has uinput access.

## Windows

Windows 10+ on x64. Fastest path — download the prebuilt `guiport-<ver>-windows-x64.zip` from the [latest release](https://github.com/edihasaj/guiport/releases/latest) and unzip it anywhere. The Swift runtime DLLs are bundled alongside `guiport.exe`, so **no Swift toolchain is required** — keep the DLLs next to the exe and add the folder to PATH.

```powershell
# from an unzipped release folder
.\guiport.exe --version
```

Or build from source — the installer clones the repo and builds via `swift build -c release`, so you need a Swift toolchain on PATH first ([swift.org/install/windows](https://www.swift.org/install/windows/)):

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
