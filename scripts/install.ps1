# Installer placeholder for guiport on Windows.
# Usage:  iwr -useb https://raw.githubusercontent.com/edihasaj/guiport/main/scripts/install.ps1 | iex
$ErrorActionPreference = "Stop"

Write-Host "[guiport] Windows is not supported at MVP." -ForegroundColor Yellow
Write-Host "[guiport] The desktop-control runtime is macOS-only. Track the Windows UIA adapter on the roadmap."
Write-Host "[guiport] See: https://github.com/edihasaj/guiport/blob/main/INSTALL.md"
exit 1
