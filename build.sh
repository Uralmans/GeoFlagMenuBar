#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP=GeoFlagMenuBar
BUILD=build
DIST="$BUILD/$APP.app"
CONTENTS="$DIST/Contents"
MACOS="$CONTENTS/MacOS"

mkdir -p "$MACOS" "$CONTENTS/Resources" "$BUILD/objs"

# Two single-arch builds, then lipo -> universal binary (Apple Silicon + Intel).
swiftc -O -module-name $APP -target arm64-apple-macos13.0 \
  Sources/$APP.swift -framework AppKit -o "$BUILD/objs/$APP.arm64"

swiftc -O -module-name $APP -target x86_64-apple-macos13.0 \
  Sources/$APP.swift -framework AppKit -o "$BUILD/objs/$APP.x86_64"

lipo -create -output "$MACOS/$APP" \
  "$BUILD/objs/$APP.arm64" "$BUILD/objs/$APP.x86_64"

# Sign the binary first, then the whole bundle (Info.plist must be in place
# before signing the bundle, otherwise the seal is invalid).
cp Info.plist "$CONTENTS/Info.plist"
codesign --force --sign - "$MACOS/$APP" 2>/dev/null || true
codesign --force --sign - "$DIST" 2>/dev/null || true

echo "Built: $DIST"
