#!/bin/zsh
# Make dist/Halfpast-<version>.dmg for anyone with a Mac: builds the universal app, signs it with the
# Developer ID (hardened runtime, secure timestamp), wraps it in a drag-to-Applications disk image,
# signs that, then notarises and staples it so Gatekeeper opens it without a warning.
#
# Notarising needs Apple credentials stored once in the keychain under the profile "notary":
#   xcrun notarytool store-credentials notary --apple-id <apple id> --team-id GAMJ6J6LT3
# (it asks for an app-specific password from account.apple.com). Without it the .dmg is signed
# but not notarised, and other Macs will warn before opening it.
set -e
cd "${0:A:h}"
IDENTITY="Developer ID Application: Rahul Matthan (GAMJ6J6LT3)"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP=build/Halfpast.app
DMG=dist/Halfpast-$VERSION.dmg

./build.sh
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"

STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Halfpast" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if xcrun notarytool history --keychain-profile notary >/dev/null 2>&1; then
  xcrun notarytool submit "$DMG" --keychain-profile notary --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=1 "$DMG"
  echo "notarised: $DMG"
else
  echo "signed but NOT notarised: $DMG — store credentials (see the top of this script) and re-run"
fi
