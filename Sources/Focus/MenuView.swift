import SwiftUI

/// 点菜单栏图标弹出的面板
struct MenuView: View {
    let store: FocusStore
    let updater = Updater.shared
    let onStart: () -> Void
    let onQuit: () -> Void

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            if updater.hasUpdate || isUpdateFailure {
                UpdateBanner(updater: updater)
                    .padding(.bottom, 16)
                    .transition(.blurReplace)
            }

            stats
                .padding(.bottom, 16)

            WeekChart(days: store.lastWeek)
                .padding(.bottom, 20)

            Button(action: onStart) {
                HStack {
                    Image(nsImage: StatusIcon.image).renderingMode(.template)
                    Text("开始专注")
                    Spacer()
                    Text("⌥⌘F").opacity(0.7)
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(BrandButtonStyle())
            .padding(.bottom, 18)

            Divider().padding(.bottom, 12)

            HStack {
                Text("离开后自动模糊")
                Spacer()
                Picker("", selection: $store.idleMinutes) {
                    ForEach(FocusStore.idleOptions, id: \.self) { minutes in
                        Text(minutes == 0 ? "关闭" : "\(minutes) 分钟").tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.bottom, 8)

            HStack {
                Text("专注画面保持亮屏")
                Spacer()
                Picker("", selection: $store.keepAwakeMinutes) {
                    ForEach(FocusStore.keepAwakeOptions, id: \.self) { minutes in
                        Text(Self.keepAwakeLabel(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .help("没人碰电脑时最多保持亮屏多久，之后按系统设置熄屏、睡眠")
            .padding(.bottom, 8)

            HStack {
                Text("音效")
                Spacer()
                Toggle("", isOn: $store.soundEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.bottom, 8)

            HStack {
                Text("登录时启动")
                Spacer()
                Toggle("", isOn: $store.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.bottom, 12)

            Divider().padding(.bottom, 8)

            HStack {
                Button("退出 Focus", action: onQuit)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { updater.check(userInitiated: true) }) {
                    Text(footerText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .contentTransition(.interpolate)
                }
                .buttonStyle(.plain)
                .disabled(updater.state == .checking)
                .help("检查更新")
            }
            .animation(.smooth, value: updater.state)
        }
        .font(.system(size: 13))
        .padding(20)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Focus").font(.system(size: 15, weight: .bold))
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var isUpdateFailure: Bool {
        if case .failed = updater.state { true } else { false }
    }

    private var footerText: String {
        let version = "v\(updater.currentVersion)"
        switch updater.state {
        case .checking: return "\(version) · 检查中…"
        case .upToDate: return "\(version) · 已是最新"
        default: return "\(version) · 检查更新"
        }
    }

    private static func keepAwakeLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "跟随系统"
        case let m where m % 60 == 0: "\(m / 60) 小时"
        case let m where m > 60: "\(Double(m) / 60) 小时"
        default: "\(minutes) 分钟"
        }
    }

    private var statusLine: String {
        if store.idleMinutes == 0 { return "自动模糊已关闭" }
        if let app = store.autoPausedBy { return "\(app) 正在播放，暂不自动模糊" }
        return "离开 \(store.idleMinutes) 分钟后自动模糊"
    }

    private var stats: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日专注")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(store.todaySeconds < 60 ? "还没开始" : DurationText.long(store.todaySeconds))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            Spacer()
            if store.streakDays > 0 {
                Label("连续 \(store.streakDays) 天", systemImage: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// 最近 7 天的专注柱状图
private struct WeekChart: View {
    let days: [(date: Date, seconds: TimeInterval)]

    var body: some View {
        let peak = max(days.map(\.seconds).max() ?? 0, 3600)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = index == days.count - 1
                VStack(spacing: 6) {
                    Capsule()
                        .fill(isToday ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.quaternary))
                        .frame(width: 12, height: max(4, 44 * day.seconds / peak))
                        .frame(height: 44, alignment: .bottom)
                    Text(isToday ? "今" : Self.weekdayName(day.date))
                        .font(.system(size: 10, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .help(DurationText.long(day.seconds))
            }
        }
    }

    private static func weekdayName(_ date: Date) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: date) - 1]
    }
}

/// 和 App 图标一致的灯火色：琥珀 → 橙红
enum Brand {
    static let gradient = LinearGradient(
        colors: [Color(red: 0.96, green: 0.60, blue: 0.24), Color(red: 0.89, green: 0.37, blue: 0.22)],
        startPoint: .leading, endPoint: .trailing)
    static let glow = Color(red: 1.0, green: 0.55, blue: 0.24)
}

/// 有新版本时卡片顶部的提示条
private struct UpdateBanner: View {
    let updater: Updater

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Brand.gradient)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if case .downloading(_, let progress) = updater.state {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Brand.glow)
                        .controlSize(.mini)
                } else {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            switch updater.state {
            case .available:
                Button("更新") { updater.install() }
                    .buttonStyle(BrandButtonStyle(compact: true))
            case .installing:
                ProgressView().controlSize(.small)
            case .failed:
                Button("重试") { updater.retry() }
                    .buttonStyle(BrandButtonStyle(compact: true))
            default:
                EmptyView()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var icon: String {
        if case .failed = updater.state { return "exclamationmark.circle.fill" }
        return "arrow.down.circle.fill"
    }

    private var title: String {
        switch updater.state {
        case .available(let version): "新版本 \(version) 可用"
        case .downloading(let version, _): "正在下载 \(version)…"
        case .installing(let version): "正在安装 \(version)…"
        case .failed: "更新没有完成"
        default: ""
        }
    }

    private var subtitle: String {
        switch updater.state {
        case .available: "当前 \(updater.currentVersion)，点更新会自动安装并重启"
        case .installing: "装好后会自动重启"
        case .failed(let message): message
        default: ""
        }
    }
}

private struct BrandButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .system(size: 12, weight: .semibold) : nil)
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 5 : 11)
            .background(Brand.gradient, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            .shadow(color: Brand.glow.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
