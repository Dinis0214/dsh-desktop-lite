#!/bin/bash
# build-icon.sh — renders the DeepSeek whale icon (blue squircle + white glyph)
# and packs it into app/Contents/Resources/icon.icns (macOS), assets/icons (Linux PNGs),
# and assets/icons/dsh-web.ico (Windows).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "")"
SDK_FLAG=""
[ -n "$SDK_PATH" ] && SDK_FLAG="-sdk $SDK_PATH"

swiftc $SDK_FLAG -O "$ROOT/scripts/build-icon.swift" -o "$TMP/build-icon-bin"
"$TMP/build-icon-bin" "$TMP/icon-1024.png"

mkdir -p "$ROOT/app/Contents/Resources"
mkdir -p "$ROOT/assets/icons"

# 1. Generate macOS iconset & icns
ICONSET="$TMP/icon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$TMP/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$TMP/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ROOT/app/Contents/Resources/icon.icns"
echo "macOS icon generated: $ROOT/app/Contents/Resources/icon.icns"

# 2. Save standard PNG icons for Linux
for s in 16 32 48 64 128 256 512; do
  mkdir -p "$ROOT/assets/icons/${s}x${s}"
  sips -z "$s" "$s" "$TMP/icon-1024.png" --out "$ROOT/assets/icons/${s}x${s}/dsh-web.png" >/dev/null 2>&1 || true
done
cp "$TMP/icon-1024.png" "$ROOT/assets/icons/dsh-web-1024.png"
echo "Linux PNG icons generated: $ROOT/assets/icons/"

# 3. Pack Windows multi-resolution .ico
python3 -c '
import os, struct

sizes = [16, 32, 48, 64, 128, 256]
png_data = []
for s in sizes:
    p = f"assets/icons/{s}x${s}/dsh-web.png"
    if os.path.exists(p):
        with open(p, "rb") as f:
            png_data.append((s, f.read()))

if png_data:
    ico_bytes = bytearray(struct.pack("<HHH", 0, 1, len(png_data)))
    offset = 6 + len(png_data) * 16
    for s, data in png_data:
        width = s if s < 256 else 0
        height = s if s < 256 else 0
        ico_bytes.extend(struct.pack("<BBBBHHII", width, height, 0, 0, 1, 32, len(data), offset))
        offset += len(data)
    for _, data in png_data:
        ico_bytes.extend(data)
    with open("assets/icons/dsh-web.ico", "wb") as f:
        f.write(ico_bytes)
    print("Windows icon generated: assets/icons/dsh-web.ico")
'
