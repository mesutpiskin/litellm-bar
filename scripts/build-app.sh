#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) LiteLLMBar.app into ./build
set -euo pipefail

VERSION="${1:-0.0.0-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/LiteLLMBar.app"

cd "$ROOT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BINS=()
for ARCH in arm64 x86_64; do
  echo "==> Building $ARCH"
  swift build -c release --triple "$ARCH-apple-macosx13.0" --scratch-path ".build/$ARCH"
  BINS+=("$(swift build -c release --triple "$ARCH-apple-macosx13.0" --scratch-path ".build/$ARCH" --show-bin-path)/LiteLLMBar")
done

lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/LiteLLMBar"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature (no Apple Developer ID required)
codesign --force --deep --sign - "$APP"

echo "==> $APP ($VERSION)"
lipo -info "$APP/Contents/MacOS/LiteLLMBar"
