#!/bin/bash
# check-service.sh — reports who owns the port, running processes, and service status.
PORT="${DSH_DESKTOP_PORT:-3080}"
echo "== 127.0.0.1:$PORT holders =="
lsof -nP -iTCP@127.0.0.1:"$PORT" -sTCP:LISTEN 2>/dev/null || echo "(free)"
echo
echo "== dsh backend processes =="
pgrep -fl "dsh.*web" 2>/dev/null || echo "(none)"
echo
echo "== launcher / GUI processes =="
pgrep -fl "dsh-web-launcher" 2>/dev/null || pgrep -fl "dsh-web" 2>/dev/null || echo "(none)"
echo

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    echo "== launchd agents (macOS) =="
    launchctl print "gui/$(id -u)/ai.deepseek.dsh-web" >/dev/null 2>&1 && echo "ai.deepseek.dsh-web: LOADED (KeepAlive daemon)" || echo "ai.deepseek.dsh-web: not loaded"
    launchctl print "gui/$(id -u)/ai.deepseek.dsh-web-desktop" >/dev/null 2>&1 && echo "ai.deepseek.dsh-web-desktop: LOADED (autostart)" || echo "ai.deepseek.dsh-web-desktop: not loaded"
elif [ "$OS" = "Linux" ]; then
    echo "== systemd user service (Linux) =="
    systemctl --user is-active dsh-web.service 2>/dev/null && echo "dsh-web.service: ACTIVE" || echo "dsh-web.service: inactive"
fi
