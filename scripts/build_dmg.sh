#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="R-Cleaner"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_VERSION="${APP_VERSION#v}"
UNIVERSAL="${UNIVERSAL:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

if [[ -n "${ARCH_LABEL:-}" ]]; then
    ARCH_TAG="$ARCH_LABEL"
elif [[ "$UNIVERSAL" == "1" ]]; then
    ARCH_TAG="universal"
else
    ARCH_TAG="$(uname -m)"
fi

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${APP_VERSION}-${ARCH_TAG}.dmg"
ZIP_NAME="${APP_NAME}-${APP_VERSION}-${ARCH_TAG}.app.zip"
DMG_PATH="$DIST_DIR/$DMG_NAME"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

if [[ ! -d "$APP_DIR" ]]; then
    echo "==> ${APP_NAME}.app not found in dist/, building it first..."
    APP_VERSION="$APP_VERSION" UNIVERSAL="$UNIVERSAL" CODESIGN_IDENTITY="$CODESIGN_IDENTITY" \
        "$ROOT_DIR/scripts/build_app.sh" release
fi

echo "==> Creating macOS installer DMG (${DMG_NAME})..."
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rcleaner-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_DIR" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    echo "==> Code signing DMG with Developer ID..."
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

echo "==> Creating notarization-friendly ZIP archive (${ZIP_NAME})..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> Generating SHA256SUMS.txt..."
(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > SHA256SUMS.txt
)

echo "==> Packaging complete:"
ls -lh "$DMG_PATH" "$ZIP_PATH" "$DIST_DIR/SHA256SUMS.txt"
cat "$DIST_DIR/SHA256SUMS.txt"
