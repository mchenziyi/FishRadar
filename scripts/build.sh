#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/FishRadar.app"
mkdir -p "$app/Contents/MacOS"
swiftc -swift-version 5 Sources/main.swift Sources/Lifecycle.swift Sources/ApproachTracker.swift Sources/RegionView.swift Sources/Settings.swift Sources/HotKeys.swift Sources/Diagnostics.swift Sources/SettingsWindow.swift -o "$app/Contents/MacOS/FishRadar" -framework AppKit -framework AVFoundation -framework Vision -framework ServiceManagement -framework Carbon
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>FishRadar</string>
<key>CFBundleIdentifier</key><string>local.fishradar.app</string>
<key>CFBundleExecutable</key><string>FishRadar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>0.2.0</string>
<key>LSUIElement</key><true/>
<key>NSCameraUsageDescription</key><string>FishRadar 使用摄像头在本机检测画面中的人员，并显示后视镜。</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
echo "构建完成：$app"
