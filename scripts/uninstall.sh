#!/bin/bash
# uninstall.sh [--purge-data] — removes the app, autostart agent/service, and optionally
# the application profile / logs (data is kept by default).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PURGE=0
[ "${1:-}" = "--purge-data" ] && PURGE=1

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    UID_NUM=$(id -u)
    LABEL_AUTOSTART="ai.deepseek.dsh-web-desktop"
    LABEL_SERVICE="ai.deepseek.dsh-web"
    APP="/Applications/DSH Web.app"
    
    pkill -f "DSH Web.app/Contents/MacOS/dsh-web-launcher" 2>/dev/null || true
    sleep 1

    launchctl bootout "gui/$UID_NUM/$LABEL_AUTOSTART" 2>/dev/null || true
    launchctl bootout "gui/$UID_NUM/$LABEL_SERVICE" 2>/dev/null || true
    
    rm -f "$HOME/Library/LaunchAgents/$LABEL_AUTOSTART.plist"
    rm -f "$HOME/Library/LaunchAgents/$LABEL_SERVICE.plist"
    
    [ -d "$APP" ] && rm -rf "$APP" && echo "app removed from /Applications"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true

    if [ "$PURGE" = "1" ]; then
      rm -rf "$HOME/Library/Application Support/DSH Web" "$HOME/Library/Logs/DSH Web"
      echo "profile & logs purged"
    else
      echo "kept: ~/Library/Application Support/DSH Web and ~/Library/Logs/DSH Web"
    fi
    echo "macOS uninstall complete"
elif [ "$OS" = "Linux" ]; then
    bash "$ROOT/scripts/uninstall-linux.sh" ${1:-}
else
    echo "Unsupported OS: $OS"
    exit 1
fi
