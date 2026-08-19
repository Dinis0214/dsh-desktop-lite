# install-windows.ps1 — installs DSH Web on Windows (to %LOCALAPPDATA%\Programs\DSH Web and creates Start Menu shortcut)
# Automatically checks for DeepSeek Harness (dsh) and installs it if missing.
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$InstallDir = "$env:LOCALAPPDATA\Programs\DSH Web"
$DistExe = "$RootDir\dist\windows\DshWeb.exe"

function Ensure-Dsh {
    Write-Host "==> 检查 DeepSeek Harness (dsh) 运行环境..."
    $dsh = Get-Command "dsh.cmd" -ErrorAction SilentlyContinue
    if (-not $dsh) { $dsh = Get-Command "dsh" -ErrorAction SilentlyContinue }
    if (-not $dsh -and (Test-Path "$env:APPDATA\npm\dsh.cmd")) { $dsh = "$env:APPDATA\npm\dsh.cmd" }

    if ($dsh) {
        Write-Host "[✓] 检测到 DeepSeek Harness 已安装。"
        return
    }

    Write-Host "[!] 本机尚未安装 DeepSeek Harness (dsh)，正在尝试自动安装..."
    $npm = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
    if (-not $npm) { $npm = Get-Command "npm" -ErrorAction SilentlyContinue }

    if ($npm) {
        Write-Host "正在通过 npm 全局安装 @deepseek-ai/dsh..."
        try {
            & npm install -g @deepseek-ai/dsh
            Write-Host "[✓] DeepSeek Harness 自动安装成功！"
            return
        } catch {
            Write-Warning "npm 安装遇到问题，请手动执行：npm install -g @deepseek-ai/dsh"
        }
    } else {
        $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Host "检测到 winget，正在尝试自动安装 Node.js..."
            try {
                & winget install --id OpenJS.NodeJS -e --silent --accept-package-agreements --accept-source-agreements
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                & npm install -g @deepseek-ai/dsh
                Write-Host "[✓] Node.js 与 DeepSeek Harness 安装完成！"
                return
            } catch {
                Write-Warning "winget 安装 Node.js 失败。"
            }
        }
        Write-Warning "请访问 https://nodejs.org 安装 Node.js，然后运行: npm install -g @deepseek-ai/dsh"
    }
}

# 1. Check and auto-install DeepSeek Harness
Ensure-Dsh

# 2. Deploy Client Files
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if (Test-Path $DistExe) {
    Copy-Item -Path "$RootDir\dist\windows\*" -Destination $InstallDir -Recurse -Force
} else {
    # If not built with dotnet, use launcher.ps1 fallback
    Copy-Item -Path "$RootDir\windows\launcher.ps1" -Destination "$InstallDir\launcher.ps1" -Force
}

# Copy icons
$IconDir = "$InstallDir\assets\icons"
New-Item -ItemType Directory -Force -Path $IconDir | Out-Null
if (Test-Path "$RootDir\assets\icons\dsh-web.ico") {
    Copy-Item -Path "$RootDir\assets\icons\dsh-web.ico" -Destination "$IconDir\dsh-web.ico" -Force
}

# Create Start Menu Shortcut
$StartMenu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$StartMenu\DSH Web.lnk")
if (Test-Path "$InstallDir\DshWeb.exe") {
    $Shortcut.TargetPath = "$InstallDir\DshWeb.exe"
} else {
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\launcher.ps1`""
}
$Shortcut.IconLocation = "$IconDir\dsh-web.ico, 0"
$Shortcut.Description = "DeepSeek Harness Desktop"
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Save()

Write-Host "Windows installation complete!"
Write-Host "You can now launch 'DSH Web' from your Start Menu."
