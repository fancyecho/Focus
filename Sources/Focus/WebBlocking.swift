import AppKit
import Carbon
import Observation

// MARK: - 网站

/// 要暂停的网站。pattern 是规整后的“域名[/路径]”，比如 bilibili.com、youtube.com/shorts。
/// 域名会连带子域名一起拦：bilibili.com 也拦 www.、m.、live.bilibili.com。
struct BlockedSite: Codable, Hashable, Identifiable {
    var pattern: String
    /// 显示名（从常用网站里选的会有，比如“哔哩哔哩”）；手输的就是 nil
    var name: String?

    var id: String { pattern }
    var displayName: String { name ?? pattern }
    /// 临时放行、拦截计数用的键，和 App 的 bundle id 不会撞
    var passKey: String { Self.passPrefix + pattern }

    static let passPrefix = "web:"

    private var parts: (host: String, path: String?) {
        let pieces = pattern.split(separator: "/", maxSplits: 1).map(String.init)
        return (pieces.first ?? pattern, pieces.count > 1 ? pieces[1] : nil)
    }

    var host: String { parts.host }

    func matches(_ url: URL) -> Bool {
        guard var host = url.host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let (patternHost, path) = parts
        guard host == patternHost || host.hasSuffix("." + patternHost) else { return false }
        guard let path else { return true }
        return url.path.lowercased().hasPrefix("/" + path)
    }

    /// 把用户输入规整成 pattern：去掉协议、www.、查询参数、末尾的斜杠；不像网址的返回 nil
    static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) { text.removeFirst(scheme.count) }
        if let cut = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<cut]) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        while text.hasSuffix("/") { text.removeLast() }
        let host = text.split(separator: "/").first.map(String.init) ?? ""
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              host.unicodeScalars.allSatisfy(allowed.contains), !text.contains(" ")
        else { return nil }
        return text
    }

    /// 常用的分心网站，点一下就能加
    static let suggestions: [BlockedSite] = [
        BlockedSite(pattern: "bilibili.com", name: "哔哩哔哩"),
        BlockedSite(pattern: "douyin.com", name: "抖音"),
        BlockedSite(pattern: "weibo.com", name: "微博"),
        BlockedSite(pattern: "zhihu.com", name: "知乎"),
        BlockedSite(pattern: "xiaohongshu.com", name: "小红书"),
        BlockedSite(pattern: "youtube.com", name: "YouTube"),
        BlockedSite(pattern: "x.com", name: "X"),
        BlockedSite(pattern: "reddit.com", name: "Reddit"),
        BlockedSite(pattern: "taobao.com", name: "淘宝"),
    ]
}

// MARK: - 浏览器

/// 能读到当前标签页网址的浏览器（都支持 AppleScript）。Firefox 不支持，读不到。
enum Browser: CaseIterable {
    case safari, chrome, arc, edge, brave, vivaldi

    var bundleID: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .arc: "company.thebrowser.Browser"
        case .edge: "com.microsoft.edgemac"
        case .brave: "com.brave.Browser"
        case .vivaldi: "com.vivaldi.Vivaldi"
        }
    }

    var name: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .arc: "Arc"
        case .edge: "Edge"
        case .brave: "Brave"
        case .vivaldi: "Vivaldi"
        }
    }

    static func from(bundleID: String?) -> Browser? {
        allCases.first { $0.bundleID == bundleID }
    }

    var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// Safari 的标签页叫 current tab，Chrome 一家（含 Arc）叫 active tab
    private var currentTab: String { self == .safari ? "current tab" : "active tab" }

    // MARK: 读网址、关标签页
    // 都包在 1～2 秒的超时里：浏览器卡住时不能把 Focus 也拖住。
    // 只有确认已经授权才会调用，绝不在这里触发授权弹窗（弹窗会卡住主线程）。

    /// 最前面窗口当前标签页的网址
    func frontURL() -> URL? {
        let source = """
        with timeout of 1 second
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return ""
                return URL of \(currentTab) of front window
            end tell
        end timeout
        """
        guard let text = run(source)?.stringValue, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    /// 关掉最前面窗口的当前标签页
    func closeFrontTab() {
        _ = run("""
        with timeout of 2 seconds
            tell application id "\(bundleID)"
                if (count of windows) > 0 then close \(currentTab) of front window
            end tell
        end timeout
        """)
    }

    /// 关掉所有网址符合条件的标签页（严格时段用）。keepFront 时保留最前窗口的当前标签页
    func closeTabs(where shouldClose: (URL) -> Bool, keepFront: Bool) {
        guard let windows = run("""
        with timeout of 2 seconds
            tell application id "\(bundleID)" to return URL of every tab of every window
        end timeout
        """) else { return }
        let front = keepFront ? frontURL() : nil
        var targets: [(window: Int, tab: Int)] = []
        for w in stride(from: windows.numberOfItems, through: 1, by: -1) {
            guard let tabs = windows.atIndex(w) else { continue }
            for t in stride(from: tabs.numberOfItems, through: 1, by: -1) {
                guard let text = tabs.atIndex(t)?.stringValue, let url = URL(string: text), shouldClose(url) else { continue }
                if w == 1, url == front { continue }
                targets.append((w, t))
            }
        }
        guard !targets.isEmpty else { return }
        // 从后往前关，前面的序号不会变
        let lines = targets.map { "close tab \($0.tab) of window \($0.window)" }.joined(separator: "\n")
        _ = run("""
        with timeout of 3 seconds
            tell application id "\(bundleID)"
                \(lines)
            end tell
        end timeout
        """)
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    // MARK: 授权

    enum Permission {
        case granted, notDetermined, denied, notRunning
    }

    /// ask = false 只查不问；ask = true 会弹系统授权框并一直等到用户选择（不要在主线程调用）
    func permission(ask: Bool) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .denied }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch Int(status) {
        case Int(noErr): return .granted
        case errAEEventWouldRequireUserConsent: return .notDetermined
        case procNotFound: return .notRunning
        default: return .denied
        }
    }

    static func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}

/// 浏览器授权状态，缓存几秒，界面和轮询共用
@Observable
final class BrowserAccess {
    static let shared = BrowserAccess()

    private(set) var states: [Browser: Browser.Permission] = [:]
    private var checkedAt: [Browser: Date] = [:]

    func isGranted(_ browser: Browser) -> Bool {
        if let at = checkedAt[browser], Date().timeIntervalSince(at) < 10, let state = states[browser] {
            return state == .granted
        }
        return refresh(browser) == .granted
    }

    @discardableResult
    func refresh(_ browser: Browser) -> Browser.Permission {
        let state = browser.permission(ask: false)
        if states[browser] != state { states[browser] = state }
        checkedAt[browser] = Date()
        return state
    }

    func refreshAll() {
        Browser.allCases.filter(\.isInstalled).forEach { refresh($0) }
    }

    /// 弹系统授权框（在后台线程等用户选择），选完刷新状态
    func request(_ browser: Browser) {
        DispatchQueue.global(qos: .userInitiated).async {
            let state = browser.permission(ask: true)
            DispatchQueue.main.async {
                self.states[browser] = state
                self.checkedAt[browser] = Date()
            }
        }
    }
}

// MARK: - 网站图标

/// 网站图标：先画一个带首字的圆角方块，再去网站自己那里取 apple-touch-icon / favicon（不经过第三方），取到就换上
@Observable
final class SiteIcons {
    static let shared = SiteIcons()

    private var icons: [String: NSImage] = [:]
    private var loading: Set<String> = []

    private static let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Focus").appendingPathComponent("SiteIcons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func icon(for site: BlockedSite) -> NSImage {
        if let icon = icons[site.host] { return icon }
        if let cached = NSImage(contentsOf: Self.cacheDirectory.appendingPathComponent("\(site.host).png")) {
            icons[site.host] = cached
            return cached
        }
        load(site.host)
        return Self.monogram(for: site)
    }

    private func load(_ host: String) {
        guard !loading.contains(host) else { return }
        loading.insert(host)
        let candidates = ["https://\(host)/apple-touch-icon.png", "https://www.\(host)/apple-touch-icon.png",
                          "https://\(host)/favicon.ico", "https://www.\(host)/favicon.ico"].compactMap(URL.init(string:))
        Task.detached(priority: .utility) {
            for url in candidates {
                var request = URLRequest(url: url)
                request.timeoutInterval = 6
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = NSImage(data: data), image.size.width >= 16,
                      let png = image.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) })?
                        .representation(using: .png, properties: [:])
                else { continue }
                try? png.write(to: Self.cacheDirectory.appendingPathComponent("\(host).png"))
                await MainActor.run { self.icons[host] = image }
                return
            }
        }
    }

    /// 取不到图标时：暖色渐变圆角方块 + 首字
    static func monogram(for site: BlockedSite) -> NSImage {
        let letter = String(site.displayName.first ?? "·").uppercased()
        let tint = RuleTint.all[abs(site.host.hashValue) % RuleTint.all.count]
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
            NSGradient(starting: NSColor(tint.0), ending: NSColor(tint.1))?.draw(in: path, angle: -60)
            let font = NSFont.systemFont(ofSize: 30, weight: .bold)
            let text = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: NSColor.white])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
    }
}
