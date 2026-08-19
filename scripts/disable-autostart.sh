#!/bin/bash
# disable-autostart.sh — stops and removes the login autostart configuration.
set -euo pipefail

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    UID_NUM=$(id -u)
    LABEL="ai.deepseek.dsh-web-desktop"
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

    launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null && echo "autostart booted out" || echo "autostart not loaded"
    [ -f "$PLIST" ] && rm "$PLIST" && echo "autostart plist removed"
    echo "macOS autostart disabled"
elif [ "$OS" = "Linux" ]; then
    rm -f "$HOME/.config/autostart/dsh-web.desktop"
    echo "Linux autostart disabled"
fi
