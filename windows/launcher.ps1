# DSH Web — Lightweight Windows Launcher (PowerShell)
# Launches DSH Web in native Edge App Window mode or checks local backend

[CmdletBinding()]
param(
    [int]$Port = 3080
)

$ErrorActionPreference = "Stop"
$HostAddr = "127.0.0.1"
$WebUrl = "http://${HostAddr}:${Port}"

function Test-PortFree ($p) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostAddr, $p, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne(500, $false)
        if (-not $wait) {
            $client.Close()
            return $true
        }
        $client.EndConnect($iar)
        $client.Close()
        return $false
    } catch {
        return $true
    }
}

function Find-Dsh {
    $dsh = Get-Command "dsh.cmd" -ErrorAction SilentlyContinue
    if ($dsh) { return $dsh.Source }
    $dsh = Get-Command "dsh" -ErrorAction SilentlyContinue
    if ($dsh) { return $dsh.Source }

    $npmDsh = "$env:APPDATA\npm\dsh.cmd"
    if (Test-Path $npmDsh) { return $npmDsh }

    return $null
}

# Start backend if port is free
if (Test-PortFree $Port) {
    $dshBin = Find-Dsh
    if ($dshBin) {
        Write-Host "Starting DeepSeek Harness backend on port $Port..."
        Start-Process -FilePath $dshBin -ArgumentList "web --port $Port" -WindowStyle Hidden
    } else {
        Write-Warning "dsh command not found. Please install via: npm install -g @deepseek-ai/dsh"
    }
}

# Wait up to 5s for port to be ready
$ready = $false
for ($i = 0; $i -lt 10; $i++) {
    if (-not (Test-PortFree $Port)) {
        $ready = $true
        break
    }
    Start-Sleep -Milliseconds 500
}

# Launch Edge in standalone App Window Mode
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edge)) {
    $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
}

if (Test-Path $edge) {
    Start-Process -FilePath $edge -ArgumentList "--app=$WebUrl", "--window-size=1360,880"
} else {
    Start-Process $WebUrl
}
