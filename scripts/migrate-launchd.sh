#!/bin/bash
# migrate-launchd.sh — manages the 24/7 launchd backend service (ai.deepseek.dsh-web)
#
#   migrate-launchd.sh --stop       disable -> bootout -> verify port free
#   migrate-launchd.sh --start      bootstrap -> enable (24/7 KeepAlive mode)
#   migrate-launchd.sh --status     show launchd service status
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UID_NUM=$(id -u)
LABEL="ai.deepseek.dsh-web"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT="${DSH_DESKTOP_PORT:-3080}"

ACTION="${1:---status}"

if [ "$ACTION" = "--start" ]; then
    if [ ! -f "$PLIST" ]; then
        echo "No plist found at $PLIST. Please run DSH Web and switch to KeepAlive mode."
        exit 1
    fi
    launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_NUM" "$PLIST"
    echo "service started (KeepAlive enabled)"
    exit 0
fi

if [ "$ACTION" = "--stop" ]; then
    launchctl disable "gui/$UID_NUM/$LABEL" 2>/dev/null || true
    if launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
        launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
        echo "service stopped"
    else
        echo "service was not running"
    fi
    exit 0
fi

# Default: --status
launchctl print "gui/$UID_NUM/$LABEL" 2>/dev/null && echo "$LABEL: active" || echo "$LABEL: not active"
