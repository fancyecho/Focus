#!/bin/bash
# 发布新版本：按 Info.plist 里的版本号构建、打包 DMG、推送代码，并在 GitHub 上创建 Release（附 Focus.dmg）。
# App 内的自动更新就是读这个 Release，所以 tag 必须是 v<版本号>，附件必须叫 Focus.dmg。
# 用法：scripts/release.sh <更新说明.md>
set -euo pipefail
cd "$(dirname "$0")/.."

NOTES=${1:?"用法：scripts/release.sh <更新说明.md>"}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

if gh release view "v$VERSION" >/dev/null 2>&1; then
    echo "v$VERSION 已经发布过了，先在 Info.plist 里把版本号改大" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "还有没提交的改动，先提交再发布" >&2
    exit 1
fi

./build.sh
scripts/make-dmg.sh
git push origin main
gh release create "v$VERSION" build/Focus.dmg --target main --title "Focus $VERSION" --notes-file "$NOTES"
echo "已发布 v$VERSION，已安装的 Focus 会在几小时内提示更新"
