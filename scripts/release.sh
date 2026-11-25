#!/usr/bin/env bash
# Build a Universal (Apple Silicon + Intel) Release Centik.app and package Centik.dmg.
#
# Optional signing & notarization (requires Apple Developer ID certificate):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="centik-notary" \
#   ./scripts/release.sh
#
# One-time notarytool keychain setup:
#   xcrun notarytool store-credentials "centik-notary" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  if ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  fi
fi

DIST_DIR="dist"
STAGE_DIR="$DIST_DIR/dmg-stage"
APP_PATH="build/Build/Products/Release/Centik.app"
DMG_PATH="$DIST_DIR/Centik.dmg"

echo "==> Building Universal Release binary (arm64 + x86_64)..."
xcodebuild \
  -project Centik.xcodeproj \
  -scheme Centik \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath build \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Signing with Developer ID: $SIGN_IDENTITY"
  codesign --deep --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
fi

echo "==> Packaging $DMG_PATH..."
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/Centik.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "Centik" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE_DIR"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Submitting to Apple notarization..."
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  echo "==> Notarized and stapled: $DMG_PATH"
else
  echo "==> Built unsigned/ad-hoc DMG: $DMG_PATH"
  echo "    (Set SIGN_IDENTITY and NOTARY_PROFILE to sign & notarize for public distribution.)"
fi
