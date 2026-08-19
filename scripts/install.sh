#!/bin/bash
# install.sh — installs DSH Web onto the host system.
# Integrates automated DeepSeek Harness runtime detection & auto-installation.
# Supports macOS (/Applications/DSH Web.app) and Linux (~/.local/bin, desktop entry, icons).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1. Ensure DeepSeek Harness is installed first
bash "$ROOT/scripts/ensure-dsh.sh" || true

# 2. Install Desktop Client
OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    APP="$ROOT/dist/DSH Web.app"
    DEST="/Applications/DSH Web.app"
    [ -d "$APP" ] || { bash "$ROOT/scripts/assemble.sh"; }

    echo "stopping running instances (if any)..."
    pkill -f "DSH Web.app/Contents/MacOS/dsh-web-launcher" 2>/dev/null || true
    sleep 1

    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    echo "copied to $DEST"

    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true
    killall Dock 2>/dev/null || true
    echo "install complete. Launch via: open -a 'DSH Web'"
elif [ "$OS" = "Linux" ]; then
    bash "$ROOT/scripts/install-linux.sh"
else
    echo "Unsupported OS: $OS"
    exit 1
fi
