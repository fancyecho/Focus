#!/bin/bash
# 打一个开发用的 Focus：bundle id 改成 com.helian.focus.dev。
# 它有自己独立的一份设置和时段，测试时随便写演示数据，不会碰到正在用的 Focus，
# 也不会和它的后台守护互相交接。
# 用法：scripts/dev-app.sh [启动参数…]，例如 scripts/dev-app.sh --show
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh >/dev/null
DEV=build/FocusDev.app
rm -rf "$DEV"
cp -R build/Focus.app "$DEV"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.helian.focus.dev" "$DEV/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName FocusDev" "$DEV/Contents/Info.plist"
# 开发版不带后台守护配置
rm -rf "$DEV/Contents/Library/LaunchAgents"
codesign --force --sign - "$DEV" 2>/dev/null

pkill -f "$DEV/Contents/MacOS/Focus" 2>/dev/null || true
open -n "$DEV" --args "$@"
echo "已启动 $DEV（设置存在 com.helian.focus.dev 里）"
