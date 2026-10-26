#!/bin/bash
# 编译并打包成 build/Focus.app
set -euo pipefail
cd "$(dirname "$0")"

# 图标只在不存在时生成一次
if [ ! -f Resources/AppIcon.icns ]; then
    mkdir -p Resources build/AppIcon.iconset
    swift scripts/make-icon.swift build/icon-1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
        sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

# 音效也只生成一次
if [ ! -d Resources/Sounds ]; then
    swift -O scripts/make-sounds.swift Resources/Sounds
fi

# 直接用 swiftc 编译：只有一个模块、没有依赖，不需要 SwiftPM。
# （SwiftPM 会扫描所有已装的 SDK，遇到残缺的 SDK 会直接报错，这样更稳）
mkdir -p .build/release
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -sdk "$(xcrun --show-sdk-path)" \
    -module-name Focus Sources/Focus/*.swift -o .build/release/Focus

APP=build/Focus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Focus "$APP/Contents/MacOS/Focus"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
mkdir -p "$APP/Contents/Library"
cp -R Resources/LaunchAgents "$APP/Contents/Library/LaunchAgents"
codesign --force --sign - "$APP"

echo "已生成 $APP"
