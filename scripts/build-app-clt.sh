#!/bin/bash
# Build FreeDisplay.app with the Command Line Tools only (no Xcode needed).
#
#   ./scripts/build-app-clt.sh            # universal (arm64 + x86_64) release build
#   ARCHS=arm64 ./scripts/build-app-clt.sh
#
# Output: build/FreeDisplay.app (ad-hoc signed)
#
# Notes:
# - The CLT toolchain ships without the SwiftUIMacros plugin, so `@State` can't be expanded
#   as a macro. The build compiles a scratch copy of the sources that uses the
#   `SwiftUI.State` property wrapper through a typealias instead (same runtime behavior).
#   The repository sources are never modified.
# - Info.plist mirrors the INFOPLIST_KEY_* settings in project.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
WORK="$BUILD/clt"
APP="$BUILD/FreeDisplay.app"
SDK="$(xcrun --show-sdk-path)"
ARCHS="${ARCHS:-arm64 x86_64}"
MIN_MACOS="14.0"

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$ROOT/project.yml")"
BUILD_NUMBER="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$ROOT/project.yml")"
: "${VERSION:?MARKETING_VERSION not found in project.yml}"
: "${BUILD_NUMBER:=1}"

echo "==> FreeDisplay $VERSION ($BUILD_NUMBER), archs: $ARCHS"
rm -rf "$WORK" "$APP"
mkdir -p "$WORK/src" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Preparing sources"
cp -R "$ROOT/FreeDisplay" "$WORK/src/"
find "$WORK/src/FreeDisplay" -name "*.swift" -exec sed -i '' 's/@State /@_CLTState /g' {} +
printf 'import SwiftUI\ntypealias _CLTState = SwiftUI.State\n' > "$WORK/src/FreeDisplay/_CLTStateShim.swift"

SLICES=()
for ARCH in $ARCHS; do
  echo "==> Compiling $ARCH"
  (cd "$WORK/src" && swiftc -O -wmo -parse-as-library \
    -sdk "$SDK" -target "$ARCH-apple-macos$MIN_MACOS" \
    -swift-version 6 -strict-concurrency=minimal \
    -module-name FreeDisplay \
    -module-cache-path "$WORK/module-cache" \
    -import-objc-header FreeDisplay/FreeDisplay-Bridging-Header.h \
    $(find FreeDisplay -name "*.swift") \
    -o "$WORK/FreeDisplay-$ARCH")
  SLICES+=("$WORK/FreeDisplay-$ARCH")
done
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/FreeDisplay"

echo "==> App icon"
ICONSET="$WORK/AppIcon.iconset"
IC="$ROOT/FreeDisplay/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICONSET"
cp "$IC/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$IC/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$IC/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$IC/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$IC/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$IC/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$IC/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$IC/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$IC/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$IC/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Info.plist"
COPYRIGHT="$(sed -n 's/^ *INFOPLIST_KEY_NSHumanReadableCopyright: *"\(.*\)"$/\1/p' "$ROOT/project.yml")"
SCREEN_CAPTURE="$(sed -n 's/^ *INFOPLIST_KEY_NSScreenCaptureUsageDescription: *"\(.*\)"$/\1/p' "$ROOT/project.yml")"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>FreeDisplay</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.freedisplay.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>FreeDisplay</string>
    <key>CFBundleDisplayName</key><string>FreeDisplay</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>$COPYRIGHT</string>
    <key>NSScreenCaptureUsageDescription</key><string>$SCREEN_CAPTURE</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Signing (ad-hoc)"
xattr -cr "$APP"
codesign --force --sign - --entitlements "$ROOT/FreeDisplay/FreeDisplay.entitlements" "$APP"
codesign --verify --strict "$APP"

echo "==> Built $APP"
lipo -info "$APP/Contents/MacOS/FreeDisplay"
