import SwiftUI

/// 点菜单栏图标弹出的面板
struct MenuView: View {
    let store: FocusStore
    let updater = Updater.shared
    let onStart: () -> Void
    let onOpenSchedules: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
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
                .padding(.bottom, 18)

            ScheduleStatusRow(action: onOpenSchedules)
                .padding(.bottom, 14)

            Button(action: onStart) {
                HStack {
                    Image(nsImage: StatusIcon.image).renderingMode(.template)
                        .accessibilityHidden(true)
                    Text("开始专注")
                    Spacer()
                    Text("⌥⌘F").opacity(0.7)
                        .accessibilityLabel("快捷键 Option Command F")
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(BrandButtonStyle())
            .padding(.bottom, 18)

            Divider().padding(.bottom, 10)

            HStack(spacing: 14) {
                Button(action: onOpenSettings) {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                // 严格时段进行中不能退出，免得一退出就绕过去了
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    let locked = ScheduleStore.shared.hasStrictRuleActive
                    Button(action: onQuit) {
                        Label(locked ? "严格时段中" : "退出", systemImage: locked ? "lock" : "power")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(locked)
                    .help(locked ? "严格时段进行中，暂时不能退出" : "退出 Focus")
                }
                Spacer()
                Button(action: { updater.check(userInitiated: true) }) {
                    Text(footerText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
                .accessibilityHidden(true)
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
                    .monospacedDigit()
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isToday ? "今天" : "星期" + Self.weekdayName(day.date))
                .accessibilityValue(day.seconds < 60 ? "没有专注" : DurationText.long(day.seconds))
            }
        }
        .animation(.smooth(duration: 0.6), value: days.map(\.seconds))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("最近 7 天专注")
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
            .overlay { Capsule().strokeBorder(.white.opacity(0.18)) }
            .shadow(color: Brand.glow.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// 卡片里的时段状态：进行中的、下一个，或者引导去设置
private struct ScheduleStatusRow: View {
    let store = ScheduleStore.shared
    let action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Button(action: action) {
                content(now: context.date)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressScaleStyle())
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let active = store.activeOccurrences(at: now).last {
            let rule = active.rule
        let blocked = store.blockedCount(on: now)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    icon(for: rule)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(rule.name).font(.system(size: 13, weight: .semibold))
                            StatusPill(text: "进行中", tint: rule.tint)
                        }
                        Text(blocked > 0
                             ? "\(ScheduleText.moment(active.end, from: now)) 结束 · 拦下 \(blocked) 次"
                             : "\(ScheduleText.moment(active.end, from: now)) 结束 · \(ScheduleText.targetList(rule))暂停")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    chevron
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(RuleTint.gradient(rule.tint))
                            .frame(width: proxy.size.width * (1 - active.progress(at: now)))
                    }
                }
                .frame(height: 3)
            }
            .padding(12)
            .background(RuleTint.color(rule.tint).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if let next = store.nextOccurrence(after: now) {
            row(icon: icon(for: next.rule),
                title: "下一段 · \(next.rule.name)",
                subtitle: "\(ScheduleText.moment(next.start, from: now)) 开始 · \(ScheduleText.targetList(next.rule))")
        } else {
            row(icon: Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 15))
                    .foregroundStyle(Brand.gradient)
                    .frame(width: 28, height: 28),
                title: "时段",
                subtitle: "在固定的时间，让分心的 App 和网站暂停")
        }
    }

    private func row(icon: some View, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            chevron
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func icon(for rule: BlockRule) -> some View {
        if rule.hasNoTargets {
            Circle().fill(RuleTint.gradient(rule.tint)).frame(width: 10, height: 10).frame(width: 28, height: 28)
        } else {
            TargetStack(rule: rule, size: 22, limit: 2).frame(minWidth: 28)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}
