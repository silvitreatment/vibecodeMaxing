#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
binary_directory="$(swift build -c release --show-bin-path)"
app_directory="$PWD/dist/Afterglow.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Helpers"
cp "$binary_directory/Afterglow" "$app_directory/Contents/MacOS/Afterglow"
cp "$binary_directory/AfterglowGuard" "$app_directory/Contents/Helpers/AfterglowGuard"
cp Resources/Info.plist "$app_directory/Contents/Info.plist"
codesign --force --sign - "$app_directory/Contents/Helpers/AfterglowGuard"
codesign --force --sign - "$app_directory"
print "Built $app_directory"
