#!/bin/bash
# Builds XPad.app (Apple Silicon + Intel) and XPad.dmg into dist/.
# Usage: scripts/build.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
BUILD="$(date +%Y%m%d%H%M)"
APP="dist/XPad.app"

echo "→ compiling (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/XPad"

echo "→ app icon"
if [ ! -f assets/AppIcon.icns ]; then
  mkdir -p assets build-icon/AppIcon.iconset
  swift scripts/make-icon.swift build-icon/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build-icon/icon-1024.png --out build-icon/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    d=$((s * 2))
    sips -z $d $d build-icon/icon-1024.png --out build-icon/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns build-icon/AppIcon.iconset -o assets/AppIcon.icns
  cp build-icon/icon-1024.png assets/icon-1024.png
  rm -rf build-icon
fi

echo "→ bundle"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/XPad"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" scripts/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ sign (ad-hoc)"
codesign --force --options runtime --sign - "$APP"
codesign --verify --strict "$APP"

echo "→ dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "scripts/First launch.txt" "$STAGE/"
hdiutil create -volname "XPad" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "dist/XPad.dmg" >/dev/null
rm -rf "$STAGE"

ls -lh dist/XPad.dmg
lipo -archs "$APP/Contents/MacOS/XPad"
