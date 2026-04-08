#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Memoir.app"
ARCHIVE_BASENAME="${1:-Memoir-macOS}"
ZIP_PATH="$DIST_DIR/${ARCHIVE_BASENAME}.zip"
DMG_PATH="$DIST_DIR/${ARCHIVE_BASENAME}.dmg"

"$ROOT_DIR/scripts/build-app.sh"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Memoir" \
  -srcfolder "$APP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created $ZIP_PATH"
echo "Created $DMG_PATH"
