#!/bin/bash
# build-linux.sh — builds Linux native binary if gcc/webkit2gtk is available, or validates Python launcher.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist/linux"
mkdir -p "$DIST"

echo "checking Linux build environment..."
if command -v gcc >/dev/null 2>&1 && (pkg-config --exists gtk+-3.0 webkit2gtk-4.1 2>/dev/null || pkg-config --exists gtk+-3.0 webkit2gtk-4.0 2>/dev/null); then
    PKG="webkit2gtk-4.1"
    pkg-config --exists webkit2gtk-4.1 || PKG="webkit2gtk-4.0"
    echo "compiling C native binary using $PKG..."
    gcc -O2 "$ROOT/linux/src/main.c" $(pkg-config --cflags --libs gtk+-3.0 "$PKG") -o "$DIST/dsh-web"
    echo "compiled: $DIST/dsh-web"
else
    echo "using Python WebKit wrapper for Linux..."
    cp "$ROOT/linux/src/dsh-web.py" "$DIST/dsh-web"
    chmod +x "$DIST/dsh-web"
    echo "prepared: $DIST/dsh-web"
fi
