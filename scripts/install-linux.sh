#!/bin/bash
# install-linux.sh — installs DSH Web on Linux (~/.local/bin, .desktop, icons, systemd)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Ensure DeepSeek Harness is installed
bash "$ROOT/scripts/ensure-dsh.sh" || true

BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
ICON_BASE="$HOME/.local/share/icons/hicolor"
SYSTEMD_DIR="$HOME/.config/systemd/user"

mkdir -p "$BIN_DIR" "$APP_DIR" "$SYSTEMD_DIR"

echo "installing DSH Web launcher to $BIN_DIR/dsh-web..."
if [ -f "$ROOT/dist/linux/dsh-web" ]; then
    cp "$ROOT/dist/linux/dsh-web" "$BIN_DIR/dsh-web"
else
    cp "$ROOT/linux/src/dsh-web.py" "$BIN_DIR/dsh-web"
fi
chmod +x "$BIN_DIR/dsh-web"

echo "installing desktop entry..."
cp "$ROOT/assets/dsh-web.desktop" "$APP_DIR/dsh-web.desktop"

echo "installing icons..."
for s in 16 32 48 64 128 256 512; do
    if [ -f "$ROOT/assets/icons/${s}x${s}/dsh-web.png" ]; then
        mkdir -p "$ICON_BASE/${s}x${s}/apps"
        cp "$ROOT/assets/icons/${s}x${s}/dsh-web.png" "$ICON_BASE/${s}x${s}/apps/dsh-web.png"
    fi
done

if [ -f "$ROOT/assets/icons/dsh-web-1024.png" ]; then
    mkdir -p "$HOME/.local/share/pixmaps"
    cp "$ROOT/assets/icons/dsh-web-1024.png" "$HOME/.local/share/pixmaps/dsh-web.png"
fi

echo "installing systemd user service..."
cp "$ROOT/assets/dsh-web.service" "$SYSTEMD_DIR/dsh-web.service"
systemctl --user daemon-reload 2>/dev/null || true

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APP_DIR" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache "$ICON_BASE" 2>/dev/null || true

echo "Linux installation completed!"
echo "You can launch DSH Web from your application menu or run 'dsh-web' in terminal."
