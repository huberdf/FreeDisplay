#!/bin/bash
# Build a release FreeDisplay.app and package it as build/FreeDisplay-<version>.dmg.
# Uses Xcode when available; otherwise falls back to the Command Line Tools build
# (scripts/build-app-clt.sh). Both produce a universal (arm64 + x86_64), ad-hoc signed app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="FreeDisplay"
BUILD_DIR="$ROOT/build"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml)"
DMG_OUTPUT="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

if xcodebuild -version >/dev/null 2>&1; then
  echo "=== Building ${APP_NAME} ${VERSION} with Xcode ==="
  # Skip Xcode's codesign; we sign manually after stripping xattrs
  xcodebuild -scheme "$APP_NAME" -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    clean build 2>&1 | tail -20
  APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/${APP_NAME}.app"
  [ -d "$APP_PATH" ] || { echo "ERROR: ${APP_NAME}.app not found in build output"; exit 1; }

  echo "=== Signing (ad-hoc) ==="
  xattr -cr "$APP_PATH"
  codesign --force --sign - --entitlements "$APP_NAME/$APP_NAME.entitlements" "$APP_PATH"
else
  echo "=== Xcode not found; building ${APP_NAME} ${VERSION} with Command Line Tools ==="
  "$ROOT/scripts/build-app-clt.sh"
  APP_PATH="$BUILD_DIR/${APP_NAME}.app"
fi

# Stage the app next to an /Applications shortcut for drag-to-install
STAGING_DIR="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "=== Creating DMG ==="
rm -f "$DMG_OUTPUT"
hdiutil create -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_OUTPUT" >/dev/null
rm -rf "$STAGING_DIR"

(cd "$BUILD_DIR" && shasum -a 256 "$(basename "$DMG_OUTPUT")" > "$(basename "$DMG_OUTPUT").sha256")

echo "=== Done ==="
ls -lh "$DMG_OUTPUT"
cat "$DMG_OUTPUT.sha256"
