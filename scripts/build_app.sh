#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-release}"
APP_NAME="R-Cleaner"
BUNDLE_ID="com.resitdc.r-cleaner"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"

echo "==> Building R-Cleaner ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/RCleaner"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: Built executable not found at $BIN_PATH"
    exit 1
fi

echo "==> Packaging ${APP_NAME}.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"

# Bundle built-in Jarvis Neural Voice Pack directly into Resources (zero user download required)
if [[ -d "$ROOT_DIR/Sources/RCleaner/Resources/VoicePack" ]]; then
    cp -R "$ROOT_DIR/Sources/RCleaner/Resources/VoicePack" "$APP_DIR/Contents/Resources/VoicePack"
fi

# Copy SwiftPM resource bundle if generated alongside the binary
RESOURCE_BUNDLE="$(swift build -c "$CONFIG" --show-bin-path)/RCleaner_RCleaner.bundle"
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>100</string>
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
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing ${APP_NAME}.app..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done! App bundle created at: $APP_DIR"
echo "    Launch with: open \"$APP_DIR\""
