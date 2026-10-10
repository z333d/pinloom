#!/bin/bash
# Builds Pinloom.app into ./build without needing Xcode.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Pinloom.app"
VERSION="0.1.3"

# Builds one architecture and prints the binary's path.
# The Command Line Tools for macOS 27 ship an SDK whose SwiftUI needs a macro
# plugin they do not include. If the default SDK fails, fall back to the
# newest macOS 26 SDK installed alongside it.
build_arch() {
  local triple="$1-apple-macosx14.0"
  if [ -z "${SDKROOT:-}" ] && ! swift build -c "$CONFIG" --triple "$triple" >&2; then
    FALLBACK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)"
    if [ -z "$FALLBACK" ]; then exit 1; fi
    echo "Retrying with $FALLBACK" >&2
    export SDKROOT="$FALLBACK"
  fi
  if [ -n "${SDKROOT:-}" ]; then swift build -c "$CONFIG" --triple "$triple" >&2; fi
  cp "$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)/Pinloom" "$OUT/Pinloom-$1"
}

# A universal binary, so it runs on Apple silicon and on Intel Macs, from
# macOS 14 Sonoma onwards.
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
build_arch arm64
build_arch x86_64
lipo -create "$OUT/Pinloom-arm64" "$OUT/Pinloom-x86_64" -output "$OUT/Pinloom"
BIN="$OUT/Pinloom"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pinloom"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp NOTICE "$APP/Contents/Resources/NOTICE"

# Icon
WORK="$(mktemp -d)"
swift scripts/make-icon.swift "$WORK/icon.png"
ICONSET="$WORK/Pinloom.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Pinloom.icns"
rm -rf "$WORK"

# Translations: one folder per language, listed in Info.plist so macOS knows
# which languages the app speaks.
LANGUAGES=""
for dir in Sources/Pinloom/Resources/*.lproj; do
  cp -R "$dir" "$APP/Contents/Resources/"
  LANGUAGES="$LANGUAGES<string>$(basename "$dir" .lproj)</string>"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pinloom</string>
  <key>CFBundleDisplayName</key><string>Pinloom</string>
  <key>CFBundleIdentifier</key><string>io.github.z333d.pinloom</string>
  <key>CFBundleExecutable</key><string>Pinloom</string>
  <key>CFBundleIconFile</key><string>Pinloom</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>${LANGUAGES}</array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Pinloom opens images you choose from the Desktop to keep them visible alongside your work.</string>
</dict>
</plist>
PLIST

# Ordinary builds always use ad hoc signing. A Developer ID is used only
# when SIGN_IDENTITY is explicitly supplied; never select a keychain identity.
IDENTITY="${SIGN_IDENTITY:--}"
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  echo "Signed with $IDENTITY"
else
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Signed ad hoc"
fi
echo "Built $APP"
