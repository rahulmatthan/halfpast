#!/bin/zsh
# Build Halfpast.app with the Command Line Tools' swiftc — no Xcode needed (same recipe as Vitals and
# Stow). Universal: Apple silicon and Intel. Signs ad hoc; build-dmg.sh signs for distribution.
# Sparkle (updates) is downloaded once into vendor/ and checked against its published checksum.
set -e
cd "${0:A:h}"
SPARKLE_VERSION=2.10.0
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
if [ ! -d vendor/Sparkle.framework ]; then
  mkdir -p vendor
  curl -sSL -o vendor/sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  vendor/sparkle.tar.xz" | shasum -a 256 -c -
  tar -xf vendor/sparkle.tar.xz -C vendor Sparkle.framework bin
  rm vendor/sparkle.tar.xz
fi

APP=build/Halfpast.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Frameworks" build/arch
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -parse-as-library -target $arch-apple-macos13.0 \
    -F vendor -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o build/arch/Halfpast-$arch Sources/*.swift
done
lipo -create build/arch/Halfpast-arm64 build/arch/Halfpast-x86_64 -output "$APP/Contents/MacOS/Halfpast"
# Halfpast isn't sandboxed, so Sparkle's XPC services aren't needed.
ditto vendor/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
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
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --identifier com.rahulmatthan.halfpast "$APP"
echo "built $APP"
