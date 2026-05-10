# guiport installer for Windows.
# Usage:  iwr -useb https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.ps1 | iex
#
# Day-1 surface (Windows beta):
#   guiport apps                          - EnumWindows + process basenames
#   guiport click-at <x> <y>              - SendInput
#   guiport type "..."                    - SendInput unicode
#   guiport hotkey ctrl+s                 - SendInput
#   guiport screenshot [--app "...]"      - GDI BitBlt / PrintWindow (writes .bmp)
#
# Pending (UIA-backed, throws clear roadmap error):
#   guiport tree / observe / find / click <selector> / find-text / record
#
# This script clones the repo and runs `swift build -c release`. A Swift toolchain
# (swift.org installer) is required. Pre-built MSI / winget package will replace
# this once the UIA surface is filled in.

$ErrorActionPreference = "Stop"

Write-Host "[guiport] Windows installer (beta — day-1 surface)" -ForegroundColor Cyan

if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
    Write-Host "[guiport] 'swift' not found on PATH." -ForegroundColor Yellow
    Write-Host "[guiport] Install the Swift toolchain from https://www.swift.org/install/windows/ and re-run."
    exit 1
}

$installDir = if ($env:GUIPORT_INSTALL_DIR) { $env:GUIPORT_INSTALL_DIR } else { "$env:LOCALAPPDATA\Programs\guiport" }
$srcDir     = Join-Path $env:TEMP "guiport-src-$(Get-Random)"

Write-Host "[guiport] cloning into $srcDir ..."
git clone --depth 1 https://github.com/edihasaj/guiport.git $srcDir | Out-Host

Push-Location $srcDir
try {
    Write-Host "[guiport] building release ..."
    swift build -c release | Out-Host

    $built = Join-Path $srcDir ".build\release\guiport.exe"
    if (-not (Test-Path $built)) {
        throw "build did not produce $built"
    }

    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Copy-Item -Force $built (Join-Path $installDir "guiport.exe")
    Write-Host "[guiport] installed to $installDir\guiport.exe" -ForegroundColor Green

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
        Write-Host "[guiport] added $installDir to user PATH (open a new shell to pick it up)"
    }

    & (Join-Path $installDir "guiport.exe") --version | Out-Host
}
finally {
    Pop-Location
    Remove-Item -Recurse -Force $srcDir -ErrorAction SilentlyContinue
}

Write-Host "[guiport] done. Try: guiport apps" -ForegroundColor Green
