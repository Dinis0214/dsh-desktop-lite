#!/bin/bash
# enable-autostart.sh — installs and loads the login LaunchAgent (macOS) or autostart desktop entry (Linux)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    UID_NUM=$(id -u)
    LABEL="ai.deepseek.dsh-web-desktop"
    PLIST_SRC="$ROOT/assets/$LABEL.plist"
    PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/DSH Web"
    sed "s|__HOME__|$HOME|g" "$PLIST_SRC" > "$PLIST_DST"
    plutil -lint "$PLIST_DST" >/dev/null || { echo "plist invalid"; exit 1; }

    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_NUM" "$PLIST_DST"
    echo "macOS autostart enabled:"
    launchctl print "gui/$UID_NUM/$LABEL" | grep -E "state|path|program" | head -5
elif [ "$OS" = "Linux" ]; then
    mkdir -p "$HOME/.config/autostart"
    cp "$ROOT/assets/dsh-web.desktop" "$HOME/.config/autostart/dsh-web.desktop"
    echo "Linux desktop autostart enabled: ~/.config/autostart/dsh-web.desktop"
fi
