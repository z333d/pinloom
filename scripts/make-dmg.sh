#!/bin/bash
# Build a disk image without opening Finder or changing desktop preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh release
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/Pinloom.app/Contents/Info.plist)"
DMG="build/Pinloom-$VERSION.dmg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stage"
cp -R build/Pinloom.app "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"
hdiutil create -ov -srcfolder "$WORK/stage" -volname Pinloom -format UDZO "$DMG"
IDENTITY="${SIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi
echo "Built $DMG"
