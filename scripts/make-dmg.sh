#!/bin/bash
# 把 build/Focus.app 打成可拖拽安装的 build/Focus.dmg（里面附带“应用程序”快捷方式）
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Focus.app
DMG=build/Focus.dmg
[ -d "$APP" ] || ./build.sh

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Focus" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "已生成 $DMG"
