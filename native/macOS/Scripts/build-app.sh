#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$repo_dir"
node_bin="${NODE_BIN:-node}"
"$node_bin" scripts/build.mjs
mkdir -p .local/swift-cache
export CLANG_MODULE_CACHE_PATH="$repo_dir/.local/swift-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
xcrun swift build --package-path native/macOS --scratch-path .local/macos-build --disable-sandbox -c release
binary_dir="$(xcrun swift build --package-path native/macOS --scratch-path .local/macos-build --disable-sandbox -c release --show-bin-path)"
app_dir="$repo_dir/dist/PlateLab.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/PlateLab" "$app_dir/Contents/MacOS/PlateLab"
python3 native/macOS/Scripts/bundle-resources.py "$app_dir"
codesign --force --deep --sign - "$app_dir"
ditto -c -k --keepParent "$app_dir" "$repo_dir/dist/PlateLab-Mac.zip"
printf 'Built %s\n' "$app_dir"
