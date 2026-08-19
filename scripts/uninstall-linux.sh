#!/bin/bash
# uninstall-linux.sh [--purge-data] — removes DSH Web from Linux
set -euo pipefail
PURGE=0
[ "${1:-}" = "--purge-data" ] && PURGE=1

echo "stopping running instances & services..."
pkill -f "dsh-web" 2>/dev/null || true
systemctl --user stop dsh-web.service 2>/dev/null || true
systemctl --user disable dsh-web.service 2>/dev/null || true

rm -f "$HOME/.local/bin/dsh-web"
rm -f "$HOME/.local/share/applications/dsh-web.desktop"
rm -f "$HOME/.config/systemd/user/dsh-web.service"
rm -f "$HOME/.config/autostart/dsh-web.desktop"

for s in 16 32 48 64 128 256 512; do
    rm -f "$HOME/.local/share/icons/hicolor/${s}x${s}/apps/dsh-web.png"
done
rm -f "$HOME/.local/share/pixmaps/dsh-web.png"

systemctl --user daemon-reload 2>/dev/null || true

if [ "$PURGE" = "1" ]; then
    rm -rf "$HOME/.config/dsh-web" "$HOME/.local/share/dsh-web"
    echo "data and logs purged"
else
    echo "kept: ~/.config/dsh-web and ~/.local/share/dsh-web"
fi

echo "Linux uninstall complete."
