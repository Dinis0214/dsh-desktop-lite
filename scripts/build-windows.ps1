# build-windows.ps1 — compiles the native Windows WebView2 client (C# / .NET)
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$DistDir = "$RootDir\dist\windows"

Write-Host "Building Windows native client for DSH Web..."

if (-not (Get-Command "dotnet" -ErrorAction SilentlyContinue)) {
    Write-Error "dotnet SDK not found. Please install .NET 8.0 SDK or higher."
    exit 1
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Push-Location "$RootDir\windows"
try {
    dotnet publish -c Release -r win-x64 --self-contained false -o $DistDir
    Write-Host "Build complete: $DistDir\DshWeb.exe"
} finally {
    Pop-Location
}
