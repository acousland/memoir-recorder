#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
app="$root/dist/Memoir.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/MemoirRecorderApp" "$app/Contents/MacOS/"
cp Bundle/Info.plist "$app/Contents/Info.plist"
cp Bundle/AppIcon.icns "$app/Contents/Resources/"
framework=$(find .build/artifacts/sparkle -path '*/macos-arm64_x86_64/Sparkle.framework' -type d -print -quit)
[[ -n $framework ]] || { echo 'Sparkle framework missing' >&2; exit 1; }
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$app/Contents/MacOS/MemoirRecorderApp" | grep '@executable_path/../Frameworks' >/dev/null; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$app/Contents/MacOS/MemoirRecorderApp"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(cat Assets/version)" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(cat Assets/build-number)" "$app/Contents/Info.plist"
scripts/sign-app.sh "$app"
echo "$app"
