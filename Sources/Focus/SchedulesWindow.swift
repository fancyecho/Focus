import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 窗口里当前选中的是哪个时段，还是设置页（菜单卡片上点“设置”时直接跳过去）
@Observable
final class SchedulesRouter {
    static let shared = SchedulesRouter()
    static let settings = UUID(uuidString: "00000000-0000-0000-0000-00000000F0C5")!
    var selection: UUID?
}

/// 主窗口：左边半透明侧栏列出所有时段和设置，右边是编辑区。
final class SchedulesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(settings: Bool = false) {
        if settings { SchedulesRouter.shared.selection = SchedulesRouter.settings }
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "时段"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 780, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self

        // 整个窗口铺一层透到桌面的材质，侧栏直接用它；右边编辑区自己画不透明的底
        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        let hosting = NSHostingView(rootView: SchedulesView(store: .shared))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: material.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        window.contentView = material
        window.center()
        window.makeKeyAndOrderFront(nil)
        // 菜单栏 App 有时抢不到前台，窗口至少要露出来
        window.orderFrontRegardless()
        // 别一打开就选中名字输入框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { window.makeFirstResponder(nil) }
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - 整体布局

struct SchedulesView: View {
    @Bindable var store: ScheduleStore
    @Bindable var router = SchedulesRouter.shared

    private var selection: UUID? {
        get { router.selection }
        nonmutating set { router.selection = newValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScheduleSidebar(store: store, selection: $router.selection)
                .frame(width: 270)

            Group {
                if selection == SchedulesRouter.settings {
                    SettingsPane()
                        .transition(.opacity)
                } else if let id = selection, store.rules.contains(where: { $0.id == id }) {
                    RuleEditor(rule: binding(for: id), store: store) {
                        withAnimation(.smooth) {
                            store.rules.removeAll { $0.id == id }
                            selection = store.rules.first?.id
                        }
                    }
                    .id(id)
                    .transition(.opacity)
                } else {
                    EmptySchedules(store: store, selection: $router.selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            }
        }
        .ignoresSafeArea()
        .onAppear { selection = selection ?? store.rules.first?.id }
        .animation(.smooth(duration: 0.3), value: selection)
    }

    /// 按 id 找，不按下标：删掉别的时段后下标会变
    private func binding(for id: UUID) -> Binding<BlockRule> {
        Binding(
            get: { store.rules.first { $0.id == id } ?? store.newRule() },
            set: { updated in
                if let index = store.rules.firstIndex(where: { $0.id == id }) { store.rules[index] = updated }
            })
    }
}

// MARK: - 侧栏

private struct ScheduleSidebar: View {
    @Bindable var store: ScheduleStore
    @Binding var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("时段").font(.system(size: 22, weight: .bold))
                Text("在固定的时间，让分心的 App 和网站暂停")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 54)
            .padding(.bottom, 18)

            ScrollView {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 4) {
                        ForEach(store.rules) { rule in
                            RuleRow(rule: rule, now: context.date, selected: selection == rule.id,
                                    locked: store.isLocked(rule, at: context.date),
                                    isEnabled: enabledBinding(rule.id))
                                .onTapGesture { selection = rule.id }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .scrollIndicators(.never)

            HStack(spacing: 8) {
                Button(action: addRule) {
                    Label("新建时段", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PressScaleStyle())
                .keyboardShortcut("n", modifiers: .command)
                .help("新建时段（⌘N）")

                let onSettings = selection == SchedulesRouter.settings
                Button { selection = SchedulesRouter.settings } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(onSettings ? AnyShapeStyle(Brand.glow) : AnyShapeStyle(.primary))
                        .frame(width: 36, height: 34)
                        .background(onSettings ? Brand.glow.opacity(0.16) : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PressScaleStyle())
                .keyboardShortcut(",", modifiers: .command)
                .help("设置（⌘,）")
                .accessibilityLabel("设置")
            }
            .padding(16)
        }
    }

    private func addRule() {
        let rule = store.newRule()
        withAnimation(.smooth) { store.rules.append(rule) }
        selection = rule.id
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.rules.first { $0.id == id }?.isEnabled ?? false },
            set: { value in
                if let index = store.rules.firstIndex(where: { $0.id == id }) { store.rules[index].isEnabled = value }
            })
    }
}

private struct RuleRow: View {
    let rule: BlockRule
    let now: Date
    let selected: Bool
    let locked: Bool
    @Binding var isEnabled: Bool

    var body: some View {
        let active = rule.activeOccurrence(at: now) != nil
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(RuleTint.gradient(rule.tint))
                .frame(width: 10, height: 10)
                .shadow(color: active ? RuleTint.color(rule.tint) : .clear, radius: 5)
                .opacity(rule.isEnabled ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(rule.name.isEmpty ? "未命名" : rule.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if active { StatusPill(text: "进行中", tint: rule.tint) }
                    if locked {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text(ScheduleText.summary(rule))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !rule.hasNoTargets {
                    TargetStack(rule: rule, size: 16)
                }
            }
            .opacity(rule.isEnabled ? 1 : 0.5)

            Spacer(minLength: 4)

            Toggle("启用", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(locked)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? RuleTint.color(rule.tint).opacity(0.16) : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .animation(.smooth(duration: 0.25), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - 编辑区

private struct RuleEditor: View {
    @Binding var rule: BlockRule
    let store: ScheduleStore
    let onDelete: () -> Void

    @State private var confirmingDelete = false
    @State private var editingName = false
    @State private var hoveringName = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let locked = store.isLocked(rule, at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(now: context.date)

                    if locked, let active = store.activeOccurrences(at: context.date).first(where: { $0.rule.id == rule.id }) {
                        Label("严格时段进行中，\(ScheduleText.moment(active.end)) 结束后才能修改", systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RuleTint.color(rule.tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        TargetsCard(apps: $rule.apps, sites: $rule.sites, tint: rule.tint)
                        TimeCard(rule: $rule)
                        DaysCard(weekdays: $rule.weekdays, tint: rule.tint)
                        ModeCard(isStrict: $rule.isStrict, tint: rule.tint)

                        Button("删除这个时段", role: .destructive) { confirmingDelete = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.top, 4)
                    }
                    .disabled(locked)
                    .opacity(locked ? 0.55 : 1)
                }
                .padding(.horizontal, 36)
                .padding(.top, 46)
                .padding(.bottom, 36)
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity)
                .environment(\.cardTint, rule.tint)
                // 标题后面一团时段颜色的柔光
                .background(alignment: .top) {
                    Circle()
                        .fill(RuleTint.color(rule.tint).opacity(0.2))
                        .frame(width: 520, height: 520)
                        .blur(radius: 110)
                        .offset(x: -160, y: -330)
                        .allowsHitTesting(false)
                        .animation(.smooth(duration: 0.6), value: rule.tint)
                }
            }
        }
        // 刚新建的时段直接进入改名（每次选中只触发一次）
        .onAppear { if rule.name == "新时段" { editingName = true } }
        .confirmationDialog("删除「\(rule.name)」？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive, action: onDelete)
        } message: {
            Text("这个时段和它的设置会被移除。")
        }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                nameView
                Spacer(minLength: 12)
                TintPicker(tint: $rule.tint)
            }
            StatusCapsule(rule: rule, store: store, now: now)
        }
    }

    /// 平时是标题，点一下才变成输入框，免得一打开窗口就出现光标
    @ViewBuilder
    private var nameView: some View {
        if editingName {
            TextField("时段名称", text: $rule.name)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .bold))
                .focused($nameFocused)
                .onSubmit { editingName = false }
                .onChange(of: nameFocused) { _, focused in if !focused { editingName = false } }
                .onAppear { DispatchQueue.main.async { nameFocused = true } }
                .onExitCommand { editingName = false }
        } else {
            HStack(spacing: 10) {
                Text(rule.name.isEmpty ? "未命名" : rule.name)
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(1)
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(hoveringName ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onHover { hoveringName = $0 }
            .onTapGesture { if !store.isLocked(rule) { editingName = true } }
            .animation(.smooth(duration: 0.15), value: hoveringName)
            .help("点击改名")
        }
    }
}

/// 标题下面的状态胶囊：进行中的带一个剩余进度小圆环
private struct StatusCapsule: View {
    let rule: BlockRule
    let store: ScheduleStore
    let now: Date

    var body: some View {
        let tint = RuleTint.color(rule.tint)
        HStack(spacing: 7) {
            switch state {
            case .active(let occurrence):
                ZStack {
                    Circle().stroke(tint.opacity(0.25), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: 1 - occurrence.progress(at: now))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12)
                Text("进行中 · \(ScheduleText.moment(occurrence.end, from: now)) 结束 · 还剩 \(ScheduleText.remaining(until: occurrence.end, from: now))")
            case .next(let occurrence):
                Image(systemName: "clock")
                Text("下一次 · \(ScheduleText.moment(occurrence.start, from: now)) 开始")
            case .message(let icon, let text):
                Image(systemName: icon)
                Text(text)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(isActive ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(isActive ? tint.opacity(0.14) : Color.primary.opacity(0.055), in: Capsule())
        .contentTransition(.interpolate)
        .animation(.smooth, value: isActive)
    }

    private enum State {
        case active(Occurrence), next(Occurrence), message(String, String)
    }

    private var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    private var state: State {
        if !rule.isEnabled { return .message("pause.circle", "已停用") }
        if rule.hasNoTargets { return .message("exclamationmark.circle", "还没有选要暂停的 App 或网站") }
        if let active = store.activeOccurrences(at: now).first(where: { $0.rule.id == rule.id }) { return .active(active) }
        if let next = rule.nextOccurrence(after: now) { return .next(next) }
        return .message("calendar.badge.exclamationmark", "当前设置下不会生效，选一下重复的日子")
    }
}

private struct TintPicker: View {
    @Binding var tint: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(RuleTint.all.indices, id: \.self) { index in
                Circle()
                    .fill(RuleTint.gradient(index))
                    .frame(width: 16, height: 16)
                    .padding(3)
                    .overlay { Circle().strokeBorder(Color.primary.opacity(tint == index ? 0.5 : 0), lineWidth: 1.5) }
                    .contentShape(Circle())
                    .onTapGesture { withAnimation(.snappy) { tint = index } }
                    .accessibilityLabel("颜色 \(index + 1)")
                    .accessibilityAddTraits(tint == index ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

private struct CardTintKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// 卡片标题图标的颜色：编辑时段时跟着时段颜色走
    var cardTint: Int? {
        get { self[CardTintKey.self] }
        set { self[CardTintKey.self] = newValue }
    }
}

/// 设置区的卡片
private struct Card<Content: View>: View {
    let title: String
    let icon: String
    var trailing: String?
    @ViewBuilder let content: Content
    @Environment(\.cardTint) private var tint

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(tint.map { AnyShapeStyle(RuleTint.color($0)) } ?? AnyShapeStyle(.secondary))
                    .frame(width: 24, height: 24)
                    .background((tint.map { RuleTint.color($0) } ?? .primary).opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

// MARK: 时间

private struct TimeCard: View {
    @Binding var rule: BlockRule

    var body: some View {
        let total = rule.windows.reduce(0) { $0 + $1.durationMinutes }
        Card(title: "时间", icon: "clock", trailing: "共 \(ScheduleText.duration(total))") {
            DayTimeline(windows: $rule.windows, tint: rule.tint, timeZone: rule.timeZone)
                .padding(.top, 6)
                .padding(.bottom, 2)

            ForEach($rule.windows) { $window in
                WindowRow(window: $window, tint: rule.tint, canDelete: rule.windows.count > 1) {
                    withAnimation(.smooth) { rule.windows.removeAll { $0.id == window.id } }
                }
            }

            HStack {
                Button {
                    withAnimation(.smooth) { rule.windows.append(nextWindow()) }
                } label: {
                    Label("添加一段", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RuleTint.color(rule.tint))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("拖动色块调整时间，在空白处拖动添加一段")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 新加的一段接在最后一段后面一小时
    private func nextWindow() -> TimeWindow {
        let start = ((rule.windows.last?.end ?? 18 * 60) + 60) % 1440
        return TimeWindow(start: start, end: (start + 120) % 1440)
    }
}

/// 24 小时时间轴，可以直接拖：拖两端改起止，拖中间整段平移，在空白处拖出新的一段。
/// 按 15 分钟吸附，碰到整点时触控板会轻轻一震。竖线是这个时区的“现在”。
private struct DayTimeline: View {
    @Binding var windows: [TimeWindow]
    let tint: Int
    let timeZone: TimeZone

    private enum Drag {
        case start(UUID)
        case end(UUID)
        case move(UUID, original: TimeWindow, anchor: Int)
        case create(UUID, anchor: Int)

        var id: UUID {
            switch self {
            case .start(let id), .end(let id), .move(let id, _, _), .create(let id, _): id
            }
        }
    }

    @State private var drag: Drag?
    @State private var lastSnapped: Int?

    private static let snap = 15
    private static let edgeSlop: CGFloat = 7
    private static let trackHeight: CGFloat = 44

    private struct Segment: Identifiable {
        let id: String
        let window: UUID
        let start: Int
        let end: Int
    }

    private var segments: [Segment] {
        windows.flatMap { window -> [Segment] in
            let end = window.end == 0 ? 1440 : window.end
            if !window.crossesMidnight || window.end == 0 {
                return [Segment(id: "\(window.id)", window: window.id, start: window.start, end: end)]
            }
            return [Segment(id: "\(window.id)-a", window: window.id, start: window.start, end: 1440),
                    Segment(id: "\(window.id)-b", window: window.id, start: 0, end: window.end)]
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .topLeading) {
                        track(width: width)
                        ForEach(segments) { segment in
                            segmentView(segment, width: width)
                        }
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 2, height: Self.trackHeight + 8)
                            .offset(x: width * nowFraction(context.date) - 1, y: -4)
                            .allowsHitTesting(false)
                        if let drag, let window = windows.first(where: { $0.id == drag.id }) {
                            dragBubble(window, width: width)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(width: width))
                    .onContinuousHover { phase in updateCursor(phase, width: width) }
                }
                .frame(height: Self.trackHeight)

                hourLabels
            }
        }
        .accessibilityElement()
        .accessibilityLabel("时间轴：" + windows.map(ScheduleText.window).joined(separator: "，"))
    }

    // MARK: 画

    private func track(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            ForEach(1..<24) { hour in
                Rectangle()
                    .fill(Color.primary.opacity(hour % 6 == 0 ? 0.12 : 0.05))
                    .frame(width: 1, height: hour % 6 == 0 ? Self.trackHeight * 0.5 : Self.trackHeight * 0.25)
                    .offset(x: width * CGFloat(hour) / 24)
            }
        }
        .frame(height: Self.trackHeight)
    }

    private func segmentView(_ segment: Segment, width: CGFloat) -> some View {
        let active = drag?.id == segment.window
        let segmentWidth = max(6, width * CGFloat(segment.end - segment.start) / 1440)
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(RuleTint.gradient(tint))
            .overlay(alignment: .leading) { handle.opacity(segment.id.hasSuffix("-b") ? 0 : 1) }
            .overlay(alignment: .trailing) { handle.opacity(segment.id.hasSuffix("-a") ? 0 : 1) }
            .frame(width: segmentWidth, height: Self.trackHeight - 10)
            .shadow(color: RuleTint.color(tint).opacity(active ? 0.6 : 0.3), radius: active ? 10 : 6, y: 2)
            .scaleEffect(y: active ? 1.08 : 1)
            .offset(x: width * CGFloat(segment.start) / 1440, y: 5)
            .animation(.snappy(duration: 0.18), value: active)
            .allowsHitTesting(false)
    }

    private var handle: some View {
        Capsule()
            .fill(.white.opacity(0.85))
            .frame(width: 3, height: 14)
            .padding(.horizontal, 4)
    }

    private func dragBubble(_ window: TimeWindow, width: CGFloat) -> some View {
        let center = CGFloat(window.start) + CGFloat(window.durationMinutes) / 2
        let x = min(max(width * (center.truncatingRemainder(dividingBy: 1440)) / 1440, 60), width - 60)
        return Text(ScheduleText.window(window))
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.1)) }
            .fixedSize()
            .position(x: x, y: -16)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    private var hourLabels: some View {
        GeometryReader { proxy in
            ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                Text("\(hour):00")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .position(x: min(max(proxy.size.width * CGFloat(hour) / 24, 14), proxy.size.width - 16), y: 6)
            }
        }
        .frame(height: 12)
    }

    // MARK: 拖

    private func minute(at x: CGFloat, width: CGFloat) -> Int {
        let raw = Double(x / max(width, 1)) * 1440 / Double(Self.snap)
        return min(max(Int(raw.rounded()) * Self.snap, 0), 1440)
    }

    private func edgeX(_ minute: Int, width: CGFloat) -> CGFloat { width * CGFloat(minute) / 1440 }

    /// 按下的位置决定要做什么：两端改起止，中间平移，空白处新建
    private func target(at x: CGFloat, width: CGFloat) -> Drag {
        for window in windows {
            let end = window.end == 0 ? 1440 : window.end
            if abs(x - edgeX(window.start, width: width)) <= Self.edgeSlop { return .start(window.id) }
            if abs(x - edgeX(end, width: width)) <= Self.edgeSlop { return .end(window.id) }
        }
        let m = minute(at: x, width: width)
        for window in windows {
            let end = window.end == 0 ? 1440 : window.end
            let inside = window.crossesMidnight && window.end != 0 ? (m >= window.start || m <= window.end) : (m >= window.start && m <= end)
            if inside { return .move(window.id, original: window, anchor: m) }
        }
        return .create(UUID(), anchor: m)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if drag == nil {
                    let target = target(at: value.startLocation.x, width: width)
                    if case .create(let id, let anchor) = target {
                        let start = min(anchor, 1440 - Self.snap)
                        windows.append(TimeWindow(id: id, start: start, end: start + Self.snap))
                    }
                    drag = target
                    if case .move = target { NSCursor.closedHand.set() }
                }
                let m = minute(at: value.location.x, width: width)
                if m != lastSnapped {
                    if m % 60 == 0 { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                    lastSnapped = m
                }
                apply(m)
            }
            .onEnded { _ in
                drag = nil
                lastSnapped = nil
                NSCursor.arrow.set()
                // 列表按开始时间排好，和时间轴的顺序一致
                withAnimation(.smooth) { windows.sort { $0.start < $1.start } }
            }
    }

    private func apply(_ m: Int) {
        guard let drag, let index = windows.firstIndex(where: { $0.id == drag.id }) else { return }
        var window = windows[index]
        switch drag {
        case .start:
            let start = m % 1440
            guard start != window.end else { return }
            window.start = start
        case .end:
            let end = m % 1440
            guard end != window.start else { return }
            window.end = end
        case .move(_, let original, let anchor):
            let delta = m - anchor
            window.start = ((original.start + delta) % 1440 + 1440) % 1440
            window.end = ((original.end + delta) % 1440 + 1440) % 1440
        case .create(_, let anchor):
            let lower = min(anchor, m), upper = max(anchor, m)
            window.start = min(lower, 1440 - Self.snap)
            window.end = max(upper, window.start + Self.snap) % 1440
        }
        windows[index] = window
    }

    private func updateCursor(_ phase: HoverPhase, width: CGFloat) {
        guard drag == nil else { return }
        guard case .active(let point) = phase else {
            NSCursor.arrow.set()
            return
        }
        switch target(at: point.x, width: width) {
        case .start, .end: NSCursor.resizeLeftRight.set()
        case .move: NSCursor.openHand.set()
        case .create: NSCursor.crosshair.set()
        }
    }

    private func nowFraction(_ date: Date) -> CGFloat {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return CGFloat((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) / 1440
    }
}

private struct WindowRow: View {
    @Binding var window: TimeWindow
    let tint: Int
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("从").foregroundStyle(.secondary)
            ClockField(minutes: $window.start)
            Text("到").foregroundStyle(.secondary)
            ClockField(minutes: $window.end)
            if window.crossesMidnight {
                StatusPill(text: "次日", tint: tint)
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            Text(ScheduleText.duration(window.durationMinutes))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(canDelete ? 1 : 0)
            .disabled(!canDelete)
            .accessibilityLabel("删除这一段")
        }
        .font(.system(size: 13))
        .animation(.smooth(duration: 0.25), value: window)
    }
}

/// 时:分 输入框。分钟数和一个固定的 UTC 日期互转，显示时也用 UTC，避免本机时区干扰
private struct ClockField: View {
    @Binding var minutes: Int

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    var body: some View {
        DatePicker("时间", selection: Binding(
            get: { Date(timeIntervalSinceReferenceDate: TimeInterval(minutes * 60)) },
            set: { date in
                let parts = Self.utc.dateComponents([.hour, .minute], from: date)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .fixedSize()
    }
}

// MARK: 重复

private struct DaysCard: View {
    @Binding var weekdays: Set<Int>
    let tint: Int

    private static let order = [2, 3, 4, 5, 6, 7, 1]
    private static let names = [2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六", 1: "日"]
    private static let segment: CGFloat = 42
    private static let height: CGFloat = 34

    /// 连在一起的选中天数画成一整条胶囊，比七个独立的圆点轻
    private var runs: [(start: Int, count: Int)] {
        var result: [(Int, Int)] = []
        for (index, day) in Self.order.enumerated() where weekdays.contains(day) {
            if let last = result.last, last.0 + last.1 == index {
                result[result.count - 1].1 += 1
            } else {
                result.append((index, 1))
            }
        }
        return result
    }

    var body: some View {
        Card(title: "重复", icon: "repeat", trailing: ScheduleText.weekdays(weekdays)) {
            HStack(spacing: 16) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    ForEach(runs, id: \.start) { run in
                        Capsule()
                            .fill(RuleTint.gradient(tint))
                            .frame(width: Self.segment * CGFloat(run.count) - 4, height: Self.height - 4)
                            .offset(x: Self.segment * CGFloat(run.start) + 2)
                            .shadow(color: RuleTint.color(tint).opacity(0.3), radius: 4, y: 1)
                    }
                    HStack(spacing: 0) {
                        ForEach(Self.order, id: \.self) { day in
                            let on = weekdays.contains(day)
                            Text(Self.names[day] ?? "")
                                .font(.system(size: 13, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                                .frame(width: Self.segment, height: Self.height)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        if on { weekdays.remove(day) } else { weekdays.insert(day) }
                                    }
                                }
                                .accessibilityLabel("星期" + (Self.names[day] ?? ""))
                                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                        }
                    }
                }
                .frame(width: Self.segment * 7, height: Self.height)
                .animation(.snappy(duration: 0.22), value: weekdays)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    ForEach([("每天", Set(1...7)), ("工作日", Set([2, 3, 4, 5, 6])), ("周末", Set([1, 7]))], id: \.0) { preset in
                        Button(preset.0) { withAnimation(.snappy(duration: 0.22)) { weekdays = preset.1 } }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: weekdays == preset.1 ? .semibold : .regular))
                            .foregroundStyle(weekdays == preset.1 ? AnyShapeStyle(RuleTint.color(tint)) : AnyShapeStyle(.secondary))
                    }
                }
            }
        }
    }
}

// MARK: 时区

private struct ZoneCard: View {
    @Binding var timeZoneID: String?
    @State private var picking = false

    var body: some View {
        let zone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        Card(title: "时区", icon: "globe") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(timeZoneID == nil ? "跟随系统 · \(ZoneCatalog.title(for: zone))" : ZoneCatalog.title(for: zone))
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(zone.identifier) · \(TimeZoneText.offset(zone)) · \(zone.abbreviation() ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("更改…") { picking = true }
                    .popover(isPresented: $picking, arrowEdge: .trailing) {
                        TimeZonePicker(selection: $timeZoneID) { picking = false }
                    }
            }
            if let note = TimeZoneText.daylightNote(zone) {
                Label(note, systemImage: "sun.horizon")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if timeZoneID == nil {
                Text("跟随系统时，出差换了时区，时段也会按当地时间生效")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// 所有时区，带常用城市的中文名，搜中文、英文、时区名都能找到
private enum ZoneCatalog {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let offset: String
        let search: String
    }

    static let aliases: [String: String] = [
        "Asia/Shanghai": "北京 / 上海", "Asia/Hong_Kong": "香港", "Asia/Taipei": "台北", "Asia/Tokyo": "东京",
        "Asia/Seoul": "首尔", "Asia/Singapore": "新加坡", "Asia/Kolkata": "印度", "Asia/Dubai": "迪拜",
        "Europe/London": "伦敦", "Europe/Paris": "巴黎", "Europe/Berlin": "柏林", "Europe/Moscow": "莫斯科",
        "America/New_York": "纽约", "America/Chicago": "芝加哥", "America/Denver": "丹佛",
        "America/Los_Angeles": "洛杉矶", "America/Toronto": "多伦多", "America/Vancouver": "温哥华",
        "Australia/Sydney": "悉尼", "Australia/Melbourne": "墨尔本", "Pacific/Auckland": "奥克兰",
    ]

    static func title(for zone: TimeZone) -> String {
        aliases[zone.identifier] ?? TimeZoneText.name(zone)
    }

    static let entries: [Entry] = TimeZone.knownTimeZoneIdentifiers.compactMap { id in
        guard let zone = TimeZone(identifier: id) else { return nil }
        let name = TimeZoneText.name(zone)
        let alias = aliases[id]
        return Entry(id: id, title: alias ?? TimeZoneText.city(zone), subtitle: "\(name) · \(id)",
                     offset: TimeZoneText.offset(zone),
                     search: [alias ?? "", name, id, TimeZoneText.city(zone)].joined(separator: " ").lowercased())
    }
    .sorted { a, b in
        // 常用的排前面，其余按偏移量
        let ua = aliases[a.id] != nil, ub = aliases[b.id] != nil
        if ua != ub { return ua }
        let oa = TimeZone(identifier: a.id)?.secondsFromGMT() ?? 0, ob = TimeZone(identifier: b.id)?.secondsFromGMT() ?? 0
        return oa != ob ? oa < ob : a.id < b.id
    }
}

private struct TimeZonePicker: View {
    @Binding var selection: String?
    let onDone: () -> Void
    @State private var query = ""

    var body: some View {
        let matches = query.isEmpty ? ZoneCatalog.entries
            : ZoneCatalog.entries.filter { $0.search.contains(query.lowercased()) }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索城市或时区，比如 纽约、Tokyo", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .padding(12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if query.isEmpty {
                        row(id: nil, title: "跟随系统",
                            subtitle: "现在是 \(ZoneCatalog.title(for: .autoupdatingCurrent))",
                            offset: TimeZoneText.offset(.autoupdatingCurrent))
                        // 当前选的时区放在最上面，不用去长列表里找
                        if let current = ZoneCatalog.entries.first(where: { $0.id == selection }) {
                            row(id: current.id, title: current.title, subtitle: current.subtitle, offset: current.offset)
                        }
                        Divider().padding(.vertical, 4)
                    }
                    ForEach(matches) { entry in
                        row(id: entry.id, title: entry.title, subtitle: entry.subtitle, offset: entry.offset)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 360, height: 440)
    }

    private func row(id: String?, title: String, subtitle: String, offset: String) -> some View {
        Button {
            selection = id
            onDone()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(offset).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(selection == id ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selection == id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: 暂停什么

/// 暂停的 App 与网站放在同一张卡片里：已添加的统一用小块显示，下面并排是“添加 App”和网址输入框
private struct TargetsCard: View {
    @Binding var apps: [BlockedApp]
    @Binding var sites: [BlockedSite]
    let tint: Int
    @State private var input = ""
    @State private var invalid = false
    @State private var pickingApp = false
    let icons = SiteIcons.shared
    let access = BrowserAccess.shared

    private var unusedSuggestions: [BlockedSite] {
        BlockedSite.suggestions.filter { suggestion in !sites.contains { $0.pattern == suggestion.pattern } }
    }

    private var countText: String? {
        let parts = [apps.isEmpty ? nil : "\(apps.count) 个 App", sites.isEmpty ? nil : "\(sites.count) 个网站"].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Card(title: "暂停的 App 与网站", icon: "pause.circle", trailing: countText) {
            if apps.isEmpty && sites.isEmpty {
                Text("选几个容易分心的 App 或网站。时段里打开它们，就会被轻轻拦下。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 172), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(apps) { app in
                        TargetChip(icon: AppIcons.icon(for: app.bundleID), title: app.name, subtitle: "App", roundsIcon: false) {
                            withAnimation(.smooth) { apps.removeAll { $0.bundleID == app.bundleID } }
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                    ForEach(sites) { site in
                        TargetChip(icon: icons.icon(for: site), title: site.displayName,
                                   subtitle: site.name == nil ? "网站" : site.pattern, roundsIcon: true) {
                            withAnimation(.smooth) { sites.removeAll { $0.pattern == site.pattern } }
                        }
                        .help(site.pattern)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
            }

            HStack(spacing: 8) {
                Button { pickingApp = true } label: {
                    Label("添加 App", systemImage: "plus.app")
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(PressScaleStyle())
                .popover(isPresented: $pickingApp, arrowEdge: .bottom) {
                    AppPicker(selected: Set(apps.map(\.bundleID))) { picked in
                        withAnimation(.smooth) {
                            for app in picked where !apps.contains(where: { $0.bundleID == app.bundleID }) {
                                apps.append(app)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundStyle(.tertiary)
                    TextField("输入网址，比如 bilibili.com 或 youtube.com/shorts", text: $input)
                        .textFieldStyle(.plain)
                        .onSubmit(addTyped)
                        .onChange(of: input) { invalid = false }
                    if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(action: addTyped) {
                            Image(systemName: "return")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(RuleTint.color(tint))
                        }
                        .buttonStyle(.plain)
                        .help("添加这个网站")
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(invalid ? Color.red.opacity(0.6) : .clear)
                }
                .modifier(Shake(attempts: invalid ? 1 : 0))
                .animation(.default, value: invalid)
                .animation(.smooth(duration: 0.2), value: input.isEmpty)
            }
            if invalid {
                Text("这看起来不像网址，试试 bilibili.com 这样的写法")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
            }

            if !unusedSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("常用网站").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(unusedSuggestions) { suggestion in
                            Button {
                                withAnimation(.smooth) { sites.append(suggestion) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(nsImage: icons.icon(for: suggestion))
                                        .resizable()
                                        .frame(width: 14, height: 14)
                                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                                    Text(suggestion.displayName).font(.system(size: 12)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.045), in: Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(PressScaleStyle())
                            .help(suggestion.pattern)
                        }
                    }
                }
            }

            if !sites.isEmpty {
                Divider().padding(.vertical, 2)
                BrowserAccessRow(access: access)
            }
        }
    }

    private func addTyped() {
        guard let pattern = BlockedSite.normalize(input) else {
            invalid = true
            return
        }
        if !sites.contains(where: { $0.pattern == pattern }) {
            let known = BlockedSite.suggestions.first { $0.pattern == pattern }
            withAnimation(.smooth) { sites.append(known ?? BlockedSite(pattern: pattern, name: nil)) }
        }
        input = ""
    }
}

/// 已添加的 App 或网站：图标 + 名字 + 一行小字，鼠标移上去出现移除按钮
private struct TargetChip: View {
    let icon: NSImage
    let title: String
    let subtitle: String
    let roundsIcon: Bool
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: roundsIcon ? 22 : 26, height: roundsIcon ? 22 : 26)
                .clipShape(RoundedRectangle(cornerRadius: roundsIcon ? 5.5 : 0, style: .continuous))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .accessibilityLabel("移除 \(title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(hovering ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.18), value: hovering)
    }
}

/// 选 App：先列出正在运行的，找不到再去“应用程序”文件夹里挑
private struct AppPicker: View {
    let selected: Set<String>
    let onPick: ([BlockedApp]) -> Void

    private var running: [BlockedApp] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> BlockedApp? in
                guard let id = app.bundleIdentifier, id != own, seen.insert(id).inserted else { return nil }
                return BlockedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("正在运行")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(running) { app in
                        let added = selected.contains(app.bundleID)
                        Button { onPick([app]) } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: AppIcons.icon(for: app.bundleID))
                                    .resizable().frame(width: 22, height: 22)
                                Text(app.name).font(.system(size: 13))
                                Spacer()
                                Image(systemName: added ? "checkmark" : "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(added ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(added)
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 320)
            Divider()
            Button {
                onPick(Self.chooseFromApplications())
            } label: {
                Label("从「应用程序」文件夹选择…", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 300)
    }

    private static func chooseFromApplications() -> [BlockedApp] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return BlockedApp(bundleID: id, name: name)
        }
    }
}

/// 每个装了的浏览器有没有允许 Focus 读网址。没授权的给一个按钮，点了弹系统授权框
private struct BrowserAccessRow: View {
    let access: BrowserAccess

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            let browsers = Browser.allCases.filter(\.isInstalled)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("浏览器").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text("需要允许 Focus 读取当前标签页的网址；不会记录或上传浏览记录")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    ForEach(browsers, id: \.self) { browser in
                        pill(browser, state: access.states[browser])
                    }
                }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox") != nil {
                    Text("Firefox 读不到网址。需要的话，把 Firefox 整个加进「暂停的 App」")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .onAppear { access.refreshAll() }
        }
    }

    @ViewBuilder
    private func pill(_ browser: Browser, state: Browser.Permission?) -> some View {
        let icon = Image(nsImage: AppIcons.icon(for: browser.bundleID)).resizable().frame(width: 15, height: 15)
        switch state {
        case .granted:
            HStack(spacing: 5) {
                icon
                Text(browser.name)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.primary.opacity(0.045), in: Capsule())
            .help("\(browser.name) 已允许")
        case .denied:
            Button { Browser.openAutomationSettings() } label: {
                HStack(spacing: 5) { icon; Text("\(browser.name) 已拒绝 · 去设置") }
            }
            .controlSize(.small)
            .help("在「系统设置 › 隐私与安全性 › 自动化」里打开 Focus 对 \(browser.name) 的权限")
        case .notRunning:
            Button {
                NSWorkspace.shared.openApplication(at: NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID)!,
                                                   configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { access.request(browser) }
                }
            } label: {
                HStack(spacing: 5) { icon; Text("打开 \(browser.name) 并允许") }
            }
            .controlSize(.small)
        default:
            Button { access.request(browser) } label: {
                HStack(spacing: 5) { icon; Text("允许 \(browser.name)") }
            }
            .controlSize(.small)
        }
    }
}

// MARK: 严格程度

private struct ModeCard: View {
    @Binding var isStrict: Bool
    let tint: Int
    let focusStore = FocusStore.shared

    private static let guarantees = [
        "被暂停的 App 直接退出、网站标签页直接关掉，后台播放也一起停下",
        "时段内不能跳过，也不能修改、停用、删除这个时段",
        "改系统时间、换时区，都不会让它提前结束",
        "Focus 不能从菜单退出；被强行结束后会自动重开",
    ]

    var body: some View {
        Card(title: "打开被暂停的 App 时", icon: "hand.raised") {
            HStack(spacing: 12) {
                option(strict: false, title: "温和", icon: "leaf",
                       text: "收起 App。可以按住按钮再用 \(ScheduleStore.passMinutes) 分钟，每天最多 \(ScheduleStore.passesPerDay) 次")
                option(strict: true, title: "严格", icon: "lock",
                       text: "没有商量的余地，到点才结束")
            }

            if isStrict {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Self.guarantees, id: \.self) { line in
                        Label {
                            Text(line)
                        } icon: {
                            Image(systemName: "checkmark").foregroundStyle(RuleTint.color(tint))
                        }
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))

                if !focusStore.keepAlive {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("现在 Focus 被强行结束就不会重开。打开「防止被强行退出」，最后一条才成立。")
                            .font(.system(size: 11.5))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("打开") { focusStore.keepAlive = true }
                            .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if focusStore.keepAliveNeedsApproval {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("还需要在「系统设置 › 登录项」里允许 Focus 在后台运行")
                            .font(.system(size: 11.5))
                        Spacer(minLength: 8)
                        Button("去设置") { BackgroundAgent.openLoginItemsSettings() }
                            .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: isStrict)
    }

    private func option(strict: Bool, title: String, icon: String, text: String) -> some View {
        let selected = isStrict == strict
        return VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? AnyShapeStyle(RuleTint.color(tint)) : AnyShapeStyle(.primary))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(selected ? RuleTint.color(tint).opacity(0.1) : Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? RuleTint.color(tint).opacity(0.7) : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { isStrict = strict } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - 空状态

private struct EmptySchedules: View {
    let store: ScheduleStore
    @Binding var selection: UUID?

    private let presets: [(name: String, detail: String, start: Int, end: Int, days: Set<Int>)] = [
        ("晚自习", "每天 19:00–22:00", 19 * 60, 22 * 60, Set(1...7)),
        ("上午刷题", "工作日 08:30–11:30", 8 * 60 + 30, 11 * 60 + 30, [2, 3, 4, 5, 6]),
        ("睡前远离屏幕", "每天 23:00–次日 07:00", 23 * 60, 7 * 60, Set(1...7)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .padding(.bottom, 18)
            Text("还没有时段")
                .font(.system(size: 22, weight: .bold))
                .padding(.bottom, 8)
            Text("在固定的时间，让微信、视频这些容易分心的 App 暂停。\n到点自动开始，到点自动结束。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.bottom, 28)

            VStack(spacing: 8) {
                ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                    Button {
                        add(name: preset.name, start: preset.start, end: preset.end, days: preset.days)
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(RuleTint.gradient(index)).frame(width: 10, height: 10)
                            Text(preset.name).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(preset.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                            Image(systemName: "plus.circle.fill").foregroundStyle(RuleTint.color(index))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(width: 360)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(.bottom, 16)

            Button("从空白开始") { add(name: "新时段", start: 19 * 60, end: 22 * 60, days: Set(1...7)) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    private func add(name: String, start: Int, end: Int, days: Set<Int>) {
        let rule = store.newRule(name: name, start: start, end: end, weekdays: days)
        withAnimation(.smooth) { store.rules.append(rule) }
        selection = rule.id
    }
}

// MARK: - 共用的小组件

struct StatusPill: View {
    let text: String
    let tint: Int

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(RuleTint.color(tint))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RuleTint.color(tint).opacity(0.15), in: Capsule())
    }
}

/// 时段里的 App 图标和网站图标叠在一起
struct TargetStack: View {
    let rule: BlockRule
    let size: CGFloat
    var limit = 4
    let icons = SiteIcons.shared

    var body: some View {
        let images: [(id: String, image: NSImage, rounded: Bool)] =
            rule.apps.map { ($0.bundleID, AppIcons.icon(for: $0.bundleID), false) }
            + rule.sites.map { ($0.pattern, icons.icon(for: $0), true) }
        HStack(spacing: -size * 0.3) {
            ForEach(images.prefix(limit), id: \.id) { item in
                Image(nsImage: item.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: item.rounded ? size * 0.82 : size, height: item.rounded ? size * 0.82 : size)
                    .clipShape(RoundedRectangle(cornerRadius: item.rounded ? size * 0.2 : 0, style: .continuous))
                    .frame(width: size, height: size)
            }
            if images.count > limit {
                Text("+\(images.count - limit)")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, size * 0.4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(ScheduleText.targetList(rule))
    }
}

/// 几个 App 图标叠在一起
struct AppStack: View {
    let apps: [BlockedApp]
    let size: CGFloat
    var limit = 4

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(apps.prefix(limit)) { app in
                Image(nsImage: AppIcons.icon(for: app.bundleID))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            }
            if apps.count > limit {
                Text("+\(apps.count - limit)")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, size * 0.4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(ScheduleText.appList(apps))
    }
}

// MARK: - 设置

/// 设置页：从菜单卡片里搬过来的开关，分组、每项带一句说明
private struct SettingsPane: View {
    @Bindable var focus = FocusStore.shared
    @Bindable var clock = ScheduleClock.shared
    let updater = Updater.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let strictActive = ScheduleStore.shared.hasStrictRuleActive
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("设置")
                        .font(.system(size: 28, weight: .bold))
                        .padding(.bottom, 4)

                    Card(title: "专注画面", icon: "moon.stars") {
                        row("离开后自动模糊", "多久不碰电脑，屏幕就模糊下来，离开的这段也算进专注") {
                            Picker("离开后自动模糊", selection: $focus.idleMinutes) {
                                ForEach(FocusStore.idleOptions, id: \.self) { minutes in
                                    Text(minutes == 0 ? "关闭" : "\(minutes) 分钟").tag(minutes)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Divider()
                        row("保持亮屏", "专注画面显示时，没人碰电脑最多亮多久，之后按系统设置熄屏") {
                            Picker("保持亮屏", selection: $focus.keepAwakeMinutes) {
                                ForEach(FocusStore.keepAwakeOptions, id: \.self) { minutes in
                                    Text(Self.keepAwakeLabel(minutes)).tag(minutes)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Divider()
                        row("音效", "开启专注、打字解锁、回到学习时的轻声提示；离开电脑自动触发时始终静音") {
                            Toggle("音效", isOn: $focus.soundEnabled).labelsHidden().toggleStyle(.switch)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ZoneCard(timeZoneID: $clock.timeZoneID)
                            .disabled(strictActive)
                        Text(strictActive ? "严格时段进行中，暂时不能改时区" : "所有时段都按这个时区的钟表时间生效，界面上的时刻也按它显示")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }

                    Card(title: "启动与守护", icon: "shield.lefthalf.filled") {
                        row("登录时启动", focus.keepAlive ? "已包含在「防止被强行退出」里" : "开机后自动在菜单栏待命，时段才能按时生效") {
                            Toggle("登录时启动", isOn: focus.keepAlive ? .constant(true) : $focus.launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(focus.keepAlive)
                        }
                        Divider()
                        row("防止被强行退出", strictActive && focus.keepAlive
                                ? "严格时段进行中，暂时不能关闭"
                                : "被活动监视器、强制退出结束后，几秒内自动重新打开。严格时段建议打开") {
                            Toggle("防止被强行退出", isOn: $focus.keepAlive)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(strictActive && focus.keepAlive)
                        }
                        if focus.keepAliveNeedsApproval {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text("还需要在「系统设置 › 通用 › 登录项」里允许 Focus 在后台运行")
                                    .font(.system(size: 11.5))
                                Spacer(minLength: 8)
                                Button("去设置") { BackgroundAgent.openLoginItemsSettings() }
                                    .controlSize(.small)
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    Card(title: "关于", icon: "info.circle") {
                        HStack(spacing: 14) {
                            Image(nsImage: NSApp.applicationIconImage)
                                .resizable()
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Focus \(updater.currentVersion)").font(.system(size: 14, weight: .semibold))
                                Text(updateLine).font(.system(size: 11.5)).foregroundStyle(.secondary)
                                    .contentTransition(.interpolate)
                            }
                            Spacer()
                            Button("检查更新") { updater.check(userInitiated: true) }
                                .disabled(updater.state == .checking)
                            Link(destination: URL(string: "https://github.com/fancyecho/Focus")!) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("在 GitHub 上查看")
                        }
                        .animation(.smooth, value: updater.state)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 46)
                .padding(.bottom, 36)
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { focus.refreshBackgroundStatus() }
    }

    private var updateLine: String {
        switch updater.state {
        case .checking: "正在检查…"
        case .upToDate: "已经是最新版本"
        case .available(let version): "新版本 \(version) 可用，点菜单栏卡片顶部的「更新」安装"
        case .downloading, .installing: "正在更新…"
        case .failed(let message): message
        case .idle: "每 6 小时自动检查一次更新"
        }
    }

    private func row<Control: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
            }
            Spacer(minLength: 12)
            control()
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
}
