import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 时段管理窗口：左边半透明侧栏列出所有时段，右边编辑选中的那个。
final class SchedulesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
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
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScheduleSidebar(store: store, selection: $selection)
                .frame(width: 270)

            Group {
                if let id = selection, store.rules.contains(where: { $0.id == id }) {
                    RuleEditor(rule: binding(for: id), store: store) {
                        withAnimation(.smooth) {
                            store.rules.removeAll { $0.id == id }
                            selection = store.rules.first?.id
                        }
                    }
                    .id(id)
                    .transition(.opacity)
                } else {
                    EmptySchedules(store: store, selection: $selection)
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
                Text("在固定的时间，让分心的 App 暂停")
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

            Button(action: addRule) {
                Label("新建时段", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(PressScaleStyle())
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
                if !rule.apps.isEmpty {
                    AppStack(apps: rule.apps, size: 16)
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let locked = store.isLocked(rule, at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(now: context.date)

                    if locked, let active = rule.activeOccurrence(at: context.date) {
                        Label("严格时段进行中，\(ScheduleText.moment(active.end)) 结束后才能修改", systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RuleTint.color(rule.tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        TimeCard(rule: $rule)
                        DaysCard(weekdays: $rule.weekdays, tint: rule.tint)
                        ZoneCard(timeZoneID: $rule.timeZoneID)
                        AppsCard(apps: $rule.apps)
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
            }
        }
        .confirmationDialog("删除「\(rule.name)」？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive, action: onDelete)
        } message: {
            Text("这个时段和它的设置会被移除。")
        }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                TextField("时段名称", text: $rule.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold))
                TintPicker(tint: $rule.tint)
            }
            HStack(spacing: 6) {
                Circle().fill(RuleTint.color(rule.tint)).frame(width: 6, height: 6)
                Text(statusLine(now: now))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private func statusLine(now: Date) -> String {
        if !rule.isEnabled { return "已停用" }
        if rule.apps.isEmpty { return "还没有选要限制的 App" }
        if let active = rule.activeOccurrence(at: now) {
            return "进行中 · \(ScheduleText.moment(active.end, from: now)) 结束 · 还有 \(ScheduleText.remaining(until: active.end, from: now))"
        }
        if let next = rule.nextOccurrence(after: now) {
            return "下一次 · \(ScheduleText.moment(next.start, from: now)) 开始"
        }
        return "当前设置下不会生效，选一下重复的日子"
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

/// 设置区的卡片
private struct Card<Content: View>: View {
    let title: String
    let icon: String
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon)
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
            DayTimeline(windows: rule.windows, tint: rule.tint, timeZone: rule.timeZone)
                .padding(.bottom, 4)

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
                if let converted = localEquivalent() {
                    Text(converted).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 新加的一段接在最后一段后面一小时
    private func nextWindow() -> TimeWindow {
        let start = ((rule.windows.last?.end ?? 18 * 60) + 60) % 1440
        return TimeWindow(start: start, end: (start + 120) % 1440)
    }

    /// 时段用的不是本机时区时，告诉用户下一次换算到本地是几点
    private func localEquivalent() -> String? {
        guard rule.timeZone.identifier != TimeZone.autoupdatingCurrent.identifier else { return nil }
        var probe = rule
        probe.isEnabled = true
        let now = Date()
        guard let next = probe.activeOccurrence(at: now) ?? probe.nextOccurrence(after: now) else { return nil }
        return "下一次在你这里是 \(ScheduleText.span(next.start, next.end, from: now))"
    }
}

/// 24 小时时间轴：哪些时间被占用一目了然，竖线是这个时区的“现在”
private struct DayTimeline: View {
    let windows: [TimeWindow]
    let tint: Int
    let timeZone: TimeZone

    private struct Segment: Identifiable {
        let id: String
        let start: Int
        let end: Int
    }

    private var segments: [Segment] {
        windows.flatMap { window -> [Segment] in
            if !window.crossesMidnight {
                return [Segment(id: "\(window.id)", start: window.start, end: window.end)]
            }
            var parts = [Segment(id: "\(window.id)-a", start: window.start, end: 1440)]
            if window.end > 0 { parts.append(Segment(id: "\(window.id)-b", start: 0, end: window.end)) }
            return parts
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 6) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))

                        ForEach(1..<8) { index in
                            Rectangle()
                                .fill(Color.primary.opacity(index % 2 == 0 ? 0.1 : 0.05))
                                .frame(width: 1, height: height * 0.4)
                                .offset(x: width * CGFloat(index * 3) / 24)
                        }

                        ForEach(segments) { segment in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(RuleTint.gradient(tint))
                                .frame(width: max(4, width * CGFloat(segment.end - segment.start) / 1440),
                                       height: height - 8)
                                .offset(x: width * CGFloat(segment.start) / 1440)
                                .shadow(color: RuleTint.color(tint).opacity(0.35), radius: 6, y: 2)
                        }

                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 2, height: height + 8)
                            .offset(x: width * nowFraction(context.date) - 1)
                    }
                    .frame(height: height)
                }
                .frame(height: 30)
                .animation(.smooth(duration: 0.35), value: windows)

                HStack {
                    ForEach(["0:00", "6:00", "12:00", "18:00", "24:00"], id: \.self) { label in
                        Text(label)
                        if label != "24:00" { Spacer() }
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("时间轴：" + windows.map(ScheduleText.window).joined(separator: "，"))
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

    var body: some View {
        Card(title: "重复", icon: "repeat", trailing: ScheduleText.weekdays(weekdays)) {
            HStack(spacing: 8) {
                ForEach(Self.order, id: \.self) { day in
                    let on = weekdays.contains(day)
                    Text(Self.names[day] ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? .white : .primary)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle().fill(on ? AnyShapeStyle(RuleTint.gradient(tint)) : AnyShapeStyle(Color.primary.opacity(0.06)))
                        }
                        .contentShape(Circle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) {
                                if on { weekdays.remove(day) } else { weekdays.insert(day) }
                            }
                        }
                        .accessibilityLabel("星期" + (Self.names[day] ?? ""))
                        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
                Spacer(minLength: 12)
                ForEach([("每天", Set(1...7)), ("工作日", Set([2, 3, 4, 5, 6])), ("周末", Set([1, 7]))], id: \.0) { preset in
                    Button(preset.0) { withAnimation(.snappy(duration: 0.2)) { weekdays = preset.1 } }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: weekdays == preset.1 ? .semibold : .regular))
                        .foregroundStyle(weekdays == preset.1 ? AnyShapeStyle(RuleTint.color(tint)) : AnyShapeStyle(.secondary))
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

// MARK: App

private struct AppsCard: View {
    @Binding var apps: [BlockedApp]
    @State private var picking = false

    var body: some View {
        Card(title: "暂停的 App", icon: "app.badge", trailing: apps.isEmpty ? nil : "\(apps.count) 个") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(apps) { app in
                    AppTile(app: app) {
                        withAnimation(.smooth) { apps.removeAll { $0.bundleID == app.bundleID } }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Button { picking = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                        Text("添加").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 84, height: 84)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressScaleStyle())
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    AppPicker(selected: Set(apps.map(\.bundleID))) { picked in
                        withAnimation(.smooth) {
                            for app in picked where !apps.contains(where: { $0.bundleID == app.bundleID }) {
                                apps.append(app)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct AppTile: View {
    let app: BlockedApp
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: AppIcons.icon(for: app.bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            Text(app.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .frame(width: 84, height: 84)
        .background(Color.primary.opacity(hovering ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .gray)
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
            .opacity(hovering ? 1 : 0)
            .accessibilityLabel("移除 \(app.name)")
        }
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

// MARK: 严格程度

private struct ModeCard: View {
    @Binding var isStrict: Bool
    let tint: Int

    var body: some View {
        Card(title: "打开被暂停的 App 时", icon: "hand.raised") {
            HStack(spacing: 12) {
                option(strict: false, title: "温和", icon: "leaf",
                       text: "可以按住按钮再用 \(ScheduleStore.passMinutes) 分钟，每天最多 \(ScheduleStore.passesPerDay) 次")
                option(strict: true, title: "严格", icon: "lock",
                       text: "时段进行中不能跳过，也不能修改、停用、删除这个时段")
            }
        }
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
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
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
