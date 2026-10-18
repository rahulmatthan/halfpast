#!/bin/zsh
# Build Zones.app with the Command Line Tools' swiftc — no Xcode needed (same recipe as Vitals and Stow).
set -e
cd "${0:A:h}"
APP=build/Zones.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos15.0 \
  -o "$APP/Contents/MacOS/Zones" Sources/*.swift
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.rahul.zones "$APP"
echo "built $APP"
