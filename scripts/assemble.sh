#!/bin/bash
# assemble.sh — builds dist/DSH Web.app (Native AppKit/WebKit Application):
#   Swift native Universal 2 binary (arm64 + x86_64) + Info.plist + DeepSeek Squircle icon
# then ad-hoc signs the bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ -f "$ROOT/app/Contents/Resources/icon.icns" ] || { bash "$ROOT/scripts/build-icon.sh"; }

DIST="$ROOT/dist"
APP="$DIST/DSH Web.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/app/Contents/Info.plist" "$APP/Contents/Info.plist"

OUTPUT_BIN="$APP/Contents/MacOS/dsh-web-launcher"
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "")"
SDK_FLAG=""
[ -n "$SDK_PATH" ] && SDK_FLAG="-sdk $SDK_PATH"

echo "compiling native app binary (Universal 2: arm64 + x86_64)..."
BUILD_SUCCESS=0

# Attempt Universal 2 binary build
if swiftc $SDK_FLAG -O -target arm64-apple-macosx12.0 -framework AppKit -framework WebKit \
  -o "$OUTPUT_BIN-arm64" \
  "$ROOT/app/launcher/main.swift" 2>/dev/null && \
  swiftc $SDK_FLAG -O -target x86_64-apple-macosx12.0 -framework AppKit -framework WebKit \
  -o "$OUTPUT_BIN-x86_64" \
  "$ROOT/app/launcher/main.swift" 2>/dev/null; then
    lipo -create "$OUTPUT_BIN-arm64" "$OUTPUT_BIN-x86_64" -output "$OUTPUT_BIN"
    rm -f "$OUTPUT_BIN-arm64" "$OUTPUT_BIN-x86_64"
    echo "universal 2 binary successfully generated:"
    lipo -info "$OUTPUT_BIN"
    BUILD_SUCCESS=1
fi

# Fallback to host architecture if universal target flags fail
if [ "$BUILD_SUCCESS" -eq 0 ]; then
    echo "universal build unavailable, falling back to host architecture compilation..."
    swiftc $SDK_FLAG -O -framework AppKit -framework WebKit \
      -o "$OUTPUT_BIN" \
      "$ROOT/app/launcher/main.swift"
    echo "host architecture binary generated:"
    file "$OUTPUT_BIN"
fi

cp "$ROOT/app/Contents/Resources/icon.icns" "$APP/Contents/Resources/icon.icns"

codesign --force --deep -s - "$APP"
echo "assembled: $APP"
du -sh "$APP"
