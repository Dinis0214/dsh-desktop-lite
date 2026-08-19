# uninstall-windows.ps1 [-PurgeData] — uninstalls DSH Web from Windows
[CmdletBinding()]
param(
    [switch]$PurgeData
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "Stopping running instances..."
Stop-Process -Name "DshWeb" -Force -ErrorAction SilentlyContinue

$InstallDir = "$env:LOCALAPPDATA\Programs\DSH Web"
$StartMenuShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\DSH Web.lnk"

if (Test-Path $StartMenuShortcut) {
    Remove-Item -Path $StartMenuShortcut -Force
    Write-Host "Removed Start Menu shortcut."
}

if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "Removed application files from $InstallDir."
}

if ($PurgeData) {
    $AppData = "$env:APPDATA\DSH Web"
    if (Test-Path $AppData) {
        Remove-Item -Path $AppData -Recurse -Force
        Write-Host "Removed configuration and logs from $AppData."
    }
} else {
    Write-Host "Kept configuration in $env:APPDATA\DSH Web."
}

Write-Host "Windows uninstallation complete."
