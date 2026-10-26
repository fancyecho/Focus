import AppKit
import Observation
import SwiftUI

/// 一天里的一段时间，按所在时区的“钟表时间”记，单位是从午夜起的分钟数。
/// end <= start 表示跨过午夜，到第二天结束。
struct TimeWindow: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Int
    var end: Int

    var crossesMidnight: Bool { end <= start }

    var durationMinutes: Int {
        let minutes = (end - start + 1440) % 1440
        return minutes == 0 ? 1440 : minutes
    }
}

struct BlockedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// 一个“时段”：在哪些天、哪几段时间、按哪个时区，限制哪些 App。
struct BlockRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var tint: Int
    var isEnabled = true
    /// nil = 跟随系统时区（出差、换时区时自动跟着变）
    var timeZoneID: String?
    /// Calendar 的星期：1 = 周日 … 7 = 周六
    var weekdays: Set<Int>
    var windows: [TimeWindow]
    var apps: [BlockedApp]
    /// 严格：进行中不能跳过，也不能修改、停用或删除这个时段
    var isStrict = false

    var timeZone: TimeZone {
        timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    func blocks(_ bundleID: String) -> Bool {
        apps.contains { $0.bundleID == bundleID }
    }
}

/// 某个时段在某一天的具体起止时刻
struct Occurrence: Equatable {
    let rule: BlockRule
    let start: Date
    let end: Date

    func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        return total > 0 ? min(max(date.timeIntervalSince(start) / total, 0), 1) : 1
    }
}

// MARK: - 时间计算

extension BlockRule {
    /// 把 window 落到 day 这一天（时段所在时区）的具体时刻上。
    ///
    /// 夏令时的处理：
    /// - 春季拨快，钟表上不存在的时刻（比如 2:30）顺延到切换之后的第一个时刻；
    /// - 秋季拨回，同一个钟点出现两次：开始取第一次，结束取第二次，
    ///   这样只要钟表显示在这段时间里，就都算在时段内。
    func occurrence(of window: TimeWindow, onDayOf day: Date) -> Occurrence? {
        let calendar = calendar
        guard weekdays.contains(calendar.component(.weekday, from: day)),
              let start = calendar.date(bySettingHour: window.start / 60, minute: window.start % 60, second: 0, of: day,
                                        matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
              let endDay = calendar.date(byAdding: .day, value: window.crossesMidnight ? 1 : 0, to: day),
              let end = calendar.date(bySettingHour: window.end / 60, minute: window.end % 60, second: 0, of: endDay,
                                      matchingPolicy: .nextTime, repeatedTimePolicy: .last, direction: .forward),
              end > start
        else { return nil }
        return Occurrence(rule: self, start: start, end: end)
    }

    /// 现在是否在这个时段里。多段时间重叠时，取结束得最晚的那段
    func activeOccurrence(at now: Date) -> Occurrence? {
        guard isEnabled else { return nil }
        return occurrences(around: now, dayOffsets: -1...0)
            .filter { $0.start <= now && now < $0.end }
            .max { $0.end < $1.end }
    }

    /// 接下来最近的一次（一周之内）
    func nextOccurrence(after now: Date) -> Occurrence? {
        guard isEnabled else { return nil }
        return occurrences(around: now, dayOffsets: 0...7)
            .filter { $0.start > now }
            .min { $0.start < $1.start }
    }

    private func occurrences(around now: Date, dayOffsets: ClosedRange<Int>) -> [Occurrence] {
        let calendar = calendar
        let today = calendar.startOfDay(for: now)
        return dayOffsets.flatMap { offset -> [Occurrence] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return windows.compactMap { occurrence(of: $0, onDayOf: day) }
        }
    }
}

// MARK: - 存储

/// 所有时段，以及“临时再用 5 分钟”的通行记录。存在 UserDefaults 里。
@Observable
final class ScheduleStore {
    static let shared = ScheduleStore()
    static let passMinutes = 5
    static let passesPerDay = 3

    private static let rulesKey = "blockRules"
    private static let passCountsKey = "blockPassCounts"

    var rules: [BlockRule] {
        didSet { save() }
    }

    /// bundle id → 临时放行到什么时候
    private(set) var passes: [String: Date] = [:]
    /// "时段 id|日期" → 当天已经用了几次临时放行
    private var passCounts: [String: Int]

    private init() {
        let defaults = UserDefaults.standard
        rules = defaults.data(forKey: Self.rulesKey)
            .flatMap { try? JSONDecoder().decode([BlockRule].self, from: $0) } ?? []
        passCounts = defaults.dictionary(forKey: Self.passCountsKey) as? [String: Int] ?? [:]
    }

    /// 这个 App 现在被哪个时段挡着（有临时放行的话就不挡）
    func blockingOccurrence(for bundleID: String, at now: Date = Date()) -> Occurrence? {
        if let pass = passes[bundleID], pass > now { return nil }
        return rules
            .filter { $0.blocks(bundleID) }
            .compactMap { $0.activeOccurrence(at: now) }
            .max { $0.end < $1.end }
    }

    func activeOccurrences(at now: Date = Date()) -> [Occurrence] {
        rules.compactMap { $0.activeOccurrence(at: now) }.sorted { $0.end < $1.end }
    }

    func nextOccurrence(after now: Date = Date()) -> Occurrence? {
        rules.compactMap { $0.nextOccurrence(after: now) }.min { $0.start < $1.start }
    }

    /// 严格时段进行中：不能修改、停用、删除
    func isLocked(_ rule: BlockRule, at now: Date = Date()) -> Bool {
        rule.isStrict && rule.activeOccurrence(at: now) != nil
    }

    var hasStrictRuleActive: Bool {
        rules.contains { isLocked($0) }
    }

    func passesLeft(for rule: BlockRule, at now: Date = Date()) -> Int {
        guard !rule.isStrict else { return 0 }
        return max(0, Self.passesPerDay - (passCounts[passKey(rule, now)] ?? 0))
    }

    func grantPass(for bundleID: String, rule: BlockRule, at now: Date = Date()) {
        guard passesLeft(for: rule, at: now) > 0 else { return }
        passCounts[passKey(rule, now), default: 0] += 1
        passes[bundleID] = now.addingTimeInterval(TimeInterval(Self.passMinutes * 60))
        // 只留最近几天的计数
        let recent = Set((0..<3).map { passKey(rule, now.addingTimeInterval(-Double($0) * 86400)) })
        passCounts = passCounts.filter { key, _ in !key.hasPrefix(rule.id.uuidString) || recent.contains(key) }
        UserDefaults.standard.set(passCounts, forKey: Self.passCountsKey)
    }

    func dropExpiredPasses(at now: Date = Date()) {
        let live = passes.filter { $0.value > now }
        if live.count != passes.count { passes = live }
    }

    func newRule(name: String = "新时段", start: Int = 19 * 60, end: Int = 22 * 60,
                 weekdays: Set<Int> = Set(1...7)) -> BlockRule {
        BlockRule(name: name, tint: rules.count % RuleTint.all.count, weekdays: weekdays,
                  windows: [TimeWindow(start: start, end: end)], apps: [])
    }

    private func passKey(_ rule: BlockRule, _ date: Date) -> String {
        let components = rule.calendar.dateComponents([.year, .month, .day], from: date)
        return "\(rule.id.uuidString)|\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: Self.rulesKey)
    }
}

// MARK: - 显示用的小工具

/// 时段的颜色：和灯火同一个色系，暖色为主
enum RuleTint {
    static let all: [(Color, Color)] = [
        (Color(red: 0.96, green: 0.60, blue: 0.24), Color(red: 0.89, green: 0.37, blue: 0.22)), // 灯火
        (Color(red: 0.93, green: 0.42, blue: 0.45), Color(red: 0.80, green: 0.28, blue: 0.43)), // 胭脂
        (Color(red: 0.62, green: 0.48, blue: 0.95), Color(red: 0.45, green: 0.34, blue: 0.86)), // 黛紫
        (Color(red: 0.36, green: 0.58, blue: 0.96), Color(red: 0.25, green: 0.42, blue: 0.86)), // 靛蓝
        (Color(red: 0.25, green: 0.74, blue: 0.70), Color(red: 0.15, green: 0.56, blue: 0.58)), // 青碧
        (Color(red: 0.55, green: 0.76, blue: 0.36), Color(red: 0.38, green: 0.60, blue: 0.27)), // 竹青
    ]

    static func gradient(_ index: Int) -> LinearGradient {
        let pair = all[index % all.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .leading, endPoint: .trailing)
    }

    static func color(_ index: Int) -> Color { all[index % all.count].0 }
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        cache[bundleID] = icon
        return icon
    }
}

enum ScheduleText {
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    static func window(_ window: TimeWindow) -> String {
        "\(clock(window.start))–\(window.crossesMidnight ? "次日 " : "")\(clock(window.end))"
    }

    static func weekdays(_ days: Set<Int>) -> String {
        switch days {
        case Set(1...7): return "每天"
        case [2, 3, 4, 5, 6]: return "工作日"
        case [1, 7]: return "周末"
        case []: return "不重复"
        default:
            let names = [2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六", 1: "日"]
            return "周" + [2, 3, 4, 5, 6, 7, 1].filter(days.contains).compactMap { names[$0] }.joined(separator: "、")
        }
    }

    static func summary(_ rule: BlockRule) -> String {
        ([weekdays(rule.weekdays)] + rule.windows.map(window)).joined(separator: " · ")
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) 分钟" }
        return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分"
    }

    static func remaining(until end: Date, from now: Date) -> String {
        duration(max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up))))
    }

    /// 本机时区的 24 小时制“时:分”（不跟系统语言走，英文系统下也不会变成 12 小时制）
    static func time(_ date: Date) -> String {
        timeFormatter.timeZone = .autoupdatingCurrent
        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 在本机时区显示的时刻；不是今天的话带上“明天”或星期
    static func moment(_ date: Date, from now: Date = Date()) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let time = time(date)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天 \(time)"
        }
        let names = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return "\(names[calendar.component(.weekday, from: date)]) \(time)"
    }

    /// 一段时间：同一天的结束只写时刻
    static func span(_ start: Date, _ end: Date, from now: Date = Date()) -> String {
        let sameDay = Calendar.autoupdatingCurrent.isDate(start, inSameDayAs: end)
        return "\(moment(start, from: now))–\(sameDay ? time(end) : moment(end, from: now))"
    }

    static func appList(_ apps: [BlockedApp]) -> String {
        switch apps.count {
        case 0: return "还没有选 App"
        case 1...2: return apps.map(\.name).joined(separator: "、")
        default: return "\(apps.prefix(2).map(\.name).joined(separator: "、")) 等 \(apps.count) 个 App"
        }
    }
}

enum TimeZoneText {
    /// UTC+8 / UTC−4 / UTC+5:30
    static func offset(_ zone: TimeZone, at date: Date = Date()) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "−"
        let h = abs(seconds) / 3600, m = abs(seconds) % 3600 / 60
        return m == 0 ? "UTC\(sign)\(h)" : String(format: "UTC%@%d:%02d", sign, h, m)
    }

    static func name(_ zone: TimeZone) -> String {
        zone.localizedName(for: .generic, locale: Locale(identifier: "zh_CN")) ?? zone.identifier
    }

    static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// “正在使用夏令时，11月2日 02:00 切回标准时间”
    static func daylightNote(_ zone: TimeZone, at date: Date = Date()) -> String? {
        guard let next = zone.nextDaylightSavingTimeTransition(after: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: next)
        let when = "\(parts.month ?? 0)月\(parts.day ?? 0)日"
        return zone.isDaylightSavingTime(for: date)
            ? "正在使用夏令时，\(when)切回标准时间，时段会自动跟着当地钟表走"
            : "\(when)开始夏令时，时段会自动跟着当地钟表走"
    }
}
