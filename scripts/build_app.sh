#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-release}"
APP_NAME="R-Cleaner"
BUNDLE_ID="com.resitdc.r-cleaner"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_VERSION="${APP_VERSION#v}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-100}"
UNIVERSAL="${UNIVERSAL:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"

BUILD_ARGS=(-c "$CONFIG")
if [[ "$UNIVERSAL" == "1" ]]; then
    echo "==> Building ${APP_NAME} ($CONFIG, universal arm64 + x86_64)..."
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
else
    echo "==> Building ${APP_NAME} ($CONFIG, native $(uname -m))..."
fi

swift build "${BUILD_ARGS[@]}"

BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/RCleaner"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Built executable not found at $BIN_PATH"
    exit 1
fi

echo "==> Packaging ${APP_NAME}.app (v${APP_VERSION}, build ${APP_BUILD_NUMBER})..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"

# Bundle built-in Clear Neural Voice Pack directly into Resources (zero user download required)
if [[ -d "$ROOT_DIR/Sources/RCleaner/Resources/VoicePack" ]]; then
    cp -R "$ROOT_DIR/Sources/RCleaner/Resources/VoicePack" "$APP_DIR/Contents/Resources/VoicePack"
fi

# Copy SwiftPM resource bundle if generated alongside the binary
RESOURCE_BUNDLE="${BIN_DIR}/RCleaner_RCleaner.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# Generate native AppIcon.icns
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Allow R-Cleaner to scan Desktop for clutter, duplicates, and potential threats.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Allow R-Cleaner to scan Documents for large files, duplicates, and potential threats.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Allow R-Cleaner to scan Downloads for installers, duplicates, and clutter.</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Allow R-Cleaner to detect similar photos and visual flaws.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Allow R-Cleaner to inspect your current Wi-Fi network security settings.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Allow R-Cleaner to listen for your two-way Clear voice commands locally on your Mac.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Allow R-Cleaner to transcribe your Clear voice commands on-device for hands-free Mac care.</string>
</dict>
</plist>
EOF

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    echo "==> Code signing ${APP_NAME}.app with Developer ID (${CODESIGN_IDENTITY})..."
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
    echo "==> Ad-hoc code signing ${APP_NAME}.app..."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Verifying code signature & architecture..."
codesign --verify --deep --strict "$APP_DIR"
file "$APP_DIR/Contents/MacOS/${APP_NAME}"

echo "==> Done! App bundle created at: $APP_DIR"
echo "    Launch with: open \"$APP_DIR\""
