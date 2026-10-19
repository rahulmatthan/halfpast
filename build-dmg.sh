#!/bin/zsh
# Make dist/Halfpast-<version>.dmg for anyone with a Mac: builds the universal app, signs it with the
# Developer ID (hardened runtime, secure timestamp), wraps it in a drag-to-Applications disk image,
# signs that, then notarises and staples it so Gatekeeper opens it without a warning. Last, it
# signs the image for Sparkle and writes docs/appcast.xml, the feed copies of Halfpast check daily.
#
# Notarising needs Apple credentials stored once in the keychain under the profile "notary":
#   xcrun notarytool store-credentials notary --apple-id <apple id> --team-id GAMJ6J6LT3
# (it asks for an app-specific password from account.apple.com). Without it the .dmg is signed
# but not notarised, and other Macs will warn before opening it.
# The appcast signature needs the Sparkle key in the login keychain (RELEASING.md).
# What's new in a version: release-notes/<version>.html (a few <li> lines), shown in the update window.
set -e
cd "${0:A:h}"
IDENTITY="Developer ID Application: Rahul Matthan (GAMJ6J6LT3)"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Resources/Info.plist)
MINOS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" Resources/Info.plist)
APP=build/Halfpast.app
DMG=dist/Halfpast-$VERSION.dmg
URL=https://exmachina.in/halfpast/Halfpast-$VERSION.dmg

./build.sh
# Inside out: Sparkle's helpers, then Sparkle, then the app — each with the hardened runtime.
SP="$APP/Contents/Frameworks/Sparkle.framework"
SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
$SIGN "$SP/Versions/B/Autoupdate"
$SIGN "$SP/Versions/B/Updater.app"
$SIGN "$SP"
$SIGN "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"

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
  exit 1
fi

# The update feed: one item, the newest version, signed with the Sparkle key (after stapling,
# since stapling changes the file).
SIG=$(vendor/bin/sign_update "$DMG")
NOTES=release-notes/$VERSION.html
cat > docs/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Halfpast</title>
    <link>https://exmachina.in/halfpast/</link>
    <item>
      <title>Halfpast $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINOS</sparkle:minimumSystemVersion>
      <description><![CDATA[$( [ -f $NOTES ] && cat $NOTES )]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIG />
    </item>
  </channel>
</rss>
XML
echo "appcast: docs/appcast.xml → $URL"
