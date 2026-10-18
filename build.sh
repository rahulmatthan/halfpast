#!/bin/zsh
# Build Halfpast.app with the Command Line Tools' swiftc — no Xcode needed (same recipe as Vitals and
# Stow). Universal: Apple silicon and Intel. Signs ad hoc; build-dmg.sh signs for distribution.
set -e
cd "${0:A:h}"
APP=build/Halfpast.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" build/arch
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -parse-as-library -target $arch-apple-macos15.0 \
    -o build/arch/Halfpast-$arch Sources/*.swift
done
lipo -create build/arch/Halfpast-arm64 build/arch/Halfpast-x86_64 -output "$APP/Contents/MacOS/Halfpast"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"
if [ ! -f Resources/AppIcon.icns ]; then
  SET=build/AppIcon.iconset; mkdir -p "$SET"
  swift scripts/make-icon.swift build/icon.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier com.rahulmatthan.halfpast "$APP"
echo "built $APP"
