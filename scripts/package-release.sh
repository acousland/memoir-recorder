#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Memoir.app"
ARCHIVE_BASENAME="${1:-Memoir-macOS}"
ZIP_PATH="$DIST_DIR/${ARCHIVE_BASENAME}.zip"
DMG_PATH="$DIST_DIR/${ARCHIVE_BASENAME}.dmg"
DMG_STAGING_DIR="$DIST_DIR/dmg-staging"

"$ROOT_DIR/scripts/build-app.sh"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
rm -f "$DMG_PATH"
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/Memoir.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "Memoir" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
rm -rf "$DMG_STAGING_DIR"

echo "Created $ZIP_PATH"
echo "Created $DMG_PATH"
