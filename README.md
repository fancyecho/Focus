<p align="center">
  <img src="docs/icon.png" width="160" alt="Focus 图标">
</p>

<h1 align="center">Focus</h1>

<p align="center">一盏青灯。离开电脑去做题时，它替你守着屏幕。</p>

Focus 是一个原生 macOS 菜单栏 App，帮你在不需要电脑的学习时段（比如做题）远离电脑。离开电脑一段时间，或按下快捷键，整个屏幕会慢慢模糊下来，只留下一句励志的话和当前时间。模糊不会自己消失，想再用电脑，得先给自己一个理由。

## 下载安装

1. 到 [Releases](https://github.com/fancyecho/Focus/releases/latest) 下载 `Focus.dmg`
2. 打开 DMG，把 Focus 拖进“应用程序”文件夹
3. 第一次打开：这个 App 没有经过苹果公证，直接双击会被系统拦下。在“应用程序”里**右键点 Focus → 打开**，再点一次“打开”即可。
   如果提示“已损坏”，在终端运行下面这行再打开：
   ```bash
   xattr -dr com.apple.quarantine /Applications/Focus.app
   ```

需要 macOS 26 或更新版本。

## 怎么用

- **开始专注**：按 `⌥⌘F`，或点菜单栏的灯形图标 →「开始专注」
- **自动触发**：离开电脑一段时间（默认 5 分钟，可在菜单里调）会自动模糊，离开的这段时间也算进专注
- **解除**，二选一：
  - 按住 `⌥⌘F` 约 4 秒，模糊会随进度慢慢揭开
  - 直接打字，输入「我现在要用电脑做正事」，打完自动解锁

## 设计

- **不打扰**：8 秒不碰电脑就进入环境模式，按钮和光标隐去，只剩一句话和时钟；专注时长只在动鼠标、或鼠标停在时钟上时才出现，不让人去追数字
- **真正的渐变模糊**：模糊半径从 0 慢慢加深，保留壁纸原有的色彩；文字一层层从模糊中浮现
- **有手感的解锁**：长按或打字时，模糊随进度一点点揭开；打字时每打对一个字响一个五声音阶的音
- **安静的音效**：全部由代码合成（见 `scripts/make-sounds.swift`）；离开电脑自动触发时静音，可在菜单里关闭
- **小结**：解锁后显示本次专注时长、今日累计和连续天数；菜单栏卡片里有最近 7 天的柱状图

## 从源码构建

只需要 Xcode 命令行工具（不需要完整 Xcode）：

```bash
./build.sh            # 生成 build/Focus.app
./scripts/make-dmg.sh # 生成 build/Focus.dmg
```

图标和音效分别由 `scripts/make-icon.swift`、`scripts/make-sounds.swift` 生成，结果已经放在 `Resources/` 里；删掉对应文件后再运行 `./build.sh` 会重新生成。
