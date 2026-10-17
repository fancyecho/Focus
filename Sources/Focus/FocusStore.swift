import Foundation
import Observation
import ServiceManagement

/// 设置和专注统计，存在 UserDefaults 里。
@Observable
final class FocusStore {
    static let shared = FocusStore()
    static let idleOptions = [0, 1, 2, 3, 5, 10, 15, 30] // 分钟，0 = 关闭
    static let keepAwakeOptions = [0, 30, 60, 90, 120] // 分钟，0 = 跟随系统

    private static let idleMinutesKey = "idleMinutes"
    private static let soundEnabledKey = "soundEnabled"
    private static let keepAwakeMinutesKey = "keepAwakeMinutes"
    private static let dailyKey = "dailyFocusSeconds"
    private static let minCountedSeconds: TimeInterval = 60

    var idleMinutes: Int {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: Self.idleMinutesKey) }
    }

    /// 专注画面显示时，没人碰电脑最多保持亮屏多久
    var keepAwakeMinutes: Int {
        didSet { UserDefaults.standard.set(keepAwakeMinutes, forKey: Self.keepAwakeMinutesKey) }
    }

    var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Self.soundEnabledKey) }
    }

    /// 有 App 在播放视频或开会时暂停自动模糊，这里记着是哪个 App（nil = 没暂停）
    var autoPausedBy: String?

    /// "yyyy-MM-dd" -> 当天专注秒数
    private(set) var daily: [String: Double]

    private init() {
        let defaults = UserDefaults.standard
        idleMinutes = defaults.object(forKey: Self.idleMinutesKey) as? Int ?? 5
        soundEnabled = defaults.object(forKey: Self.soundEnabledKey) as? Bool ?? true
        keepAwakeMinutes = defaults.object(forKey: Self.keepAwakeMinutesKey) as? Int ?? 90
        daily = defaults.dictionary(forKey: Self.dailyKey) as? [String: Double] ?? [:]
    }

    func record(_ seconds: TimeInterval, on date: Date = Date()) {
        guard seconds > 0 else { return }
        daily[Self.key(for: date), default: 0] += seconds
        UserDefaults.standard.set(daily, forKey: Self.dailyKey)
    }

    func seconds(on date: Date) -> TimeInterval {
        daily[Self.key(for: date)] ?? 0
    }

    var todaySeconds: TimeInterval { seconds(on: Date()) }

    /// 连续专注天数：今天还没专注的话，从昨天往前数。
    var streakDays: Int {
        let calendar = Calendar.current
        var day = Date()
        if seconds(on: day) < Self.minCountedSeconds {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while seconds(on: day) >= Self.minCountedSeconds {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    /// 最近 7 天（最早的在前）
    var lastWeek: [(date: Date, seconds: TimeInterval)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            return (date, seconds(on: date))
        }
    }

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Focus: 无法设置登录时启动：\(error.localizedDescription)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func key(for date: Date) -> String { formatter.string(from: date) }
}

enum DurationText {
    /// 42 分钟 / 2 小时 5 分钟
    static func long(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(rest) 分钟"
    }

    /// 计时器：12:05 / 1:02:05
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
