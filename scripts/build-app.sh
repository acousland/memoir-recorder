#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Memoir.app"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_NAME="MemoirRecorderApp"

echo "Building release executable..."
swift build -c release --package-path "$ROOT_DIR"

EXECUTABLE_PATH="$BUILD_DIR/arm64-apple-macosx/release/$EXECUTABLE_NAME"
if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

echo "Preparing app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Bundle/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

if [[ -f "$ROOT_DIR/Bundle/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Bundle/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

echo "Embedding Swift runtime libraries..."
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swift-stdlib-tool \
  --copy \
  --verbose \
  --sign - \
  --scan-executable "$MACOS_DIR/$EXECUTABLE_NAME" \
  --scan-folder "$FRAMEWORKS_DIR" \
  --destination "$FRAMEWORKS_DIR" \
  --platform macosx \
  --source-libraries "$SDK_PATH/usr/lib/swift"

echo "Codesigning app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "Created $APP_DIR"
