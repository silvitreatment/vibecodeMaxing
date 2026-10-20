#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
binary_directory="$(swift build -c release --show-bin-path)"
app_directory="$PWD/dist/vibecodeMaxing.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Helpers" "$app_directory/Contents/Resources"
swift scripts/generate-icon.swift "$PWD/dist"
cp "$PWD/dist/AppIcon.icns" "$app_directory/Contents/Resources/AppIcon.icns"
cp "$PWD/dist/LogoMark.pdf" "$app_directory/Contents/Resources/LogoMark.pdf"
cp "$binary_directory/vibecodeMaxing" "$app_directory/Contents/MacOS/vibecodeMaxing"
cp "$binary_directory/vibecodeMaxingGuard" "$app_directory/Contents/Helpers/vibecodeMaxingGuard"
cp Resources/Info.plist "$app_directory/Contents/Info.plist"
codesign --force --sign - "$app_directory/Contents/Helpers/vibecodeMaxingGuard"
codesign --force --sign - "$app_directory"
print "Built $app_directory"
