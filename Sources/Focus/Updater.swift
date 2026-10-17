import AppKit
import Observation

/// 从 GitHub Releases 自动更新。
/// 约定：Release 的 tag 是 “v版本号”（比如 v2.3），附件里有一个 Focus.dmg。
@Observable
final class Updater {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(version: String, progress: Double)
        case installing(version: String)
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?() } }
    }

    /// 有没有可装的新版本（菜单栏图标据此显示小圆点）
    var hasUpdate: Bool { state.hasUpdate }
    var onStateChange: (() -> Void)?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/fancyecho/Focus/releases/latest")!
    private static let checkInterval: TimeInterval = 6 * 3600

    private var latest: (version: String, dmg: URL)?
    private var timer: Timer?
    private var progressObservation: NSKeyValueObservation?

    private init() {}

    /// 启动后稍等一会儿检查一次，之后每 6 小时查一次
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
    }

    // MARK: 检查

    func check(userInitiated: Bool) {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        if userInitiated { state = .checking }

        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let release = data.flatMap(Self.parseRelease)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { self.finishCheck(ok ? release : nil, userInitiated: userInitiated) }
        }.resume()
    }

    private func finishCheck(_ release: (version: String, dmg: URL)?, userInitiated: Bool) {
        guard let release else {
            // 自动检查失败（比如没网）就安静地算了，手动检查才提示
            if userInitiated { state = .failed("检查失败，请稍后再试") }
            return
        }
        if Self.isVersion(release.version, newerThan: currentVersion) {
            latest = release
            state = .available(version: release.version)
        } else if userInitiated || state == .checking {
            state = .upToDate
        }
    }

    private static func parseRelease(_ data: Data) -> (version: String, dmg: URL)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as? String) == "Focus.dmg" }),
              let link = asset["browser_download_url"] as? String,
              let url = URL(string: link) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return (version, url)
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let x = i < lhs.count ? lhs[i] : 0, y = i < rhs.count ? rhs[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 失败后重试：已经知道新版本就重新安装，否则重新检查
    func retry() {
        if latest != nil { install() } else { check(userInitiated: true) }
    }

    // MARK: 安装

    /// 下载 DMG → 校验 → 替换当前 App → 重启
    func install() {
        guard let latest else { return }
        let appURL = Bundle.main.bundleURL
        if appURL.path.contains("/AppTranslocation/") {
            state = .failed("请先把 Focus 拖进「应用程序」文件夹再更新")
            return
        }

        state = .downloading(version: latest.version, progress: 0)
        let task = URLSession.shared.downloadTask(with: latest.dmg) { tempURL, response, _ in
            guard let tempURL, (response as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async { self.state = .failed("下载失败，请稍后再试") }
                return
            }
            // 临时文件在回调返回后就会被删，先挪走
            let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Focus-\(latest.version).dmg")
            try? FileManager.default.removeItem(at: dmg)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dmg)
            } catch {
                DispatchQueue.main.async { self.state = .failed("下载失败，请稍后再试") }
                return
            }
            DispatchQueue.main.async { self.state = .installing(version: latest.version) }

            do {
                try Installer.install(dmg: dmg, replacing: appURL, newerThan: self.currentVersion)
                try? FileManager.default.removeItem(at: dmg)
                DispatchQueue.main.async { Installer.relaunch(appURL) }
            } catch {
                try? FileManager.default.removeItem(at: dmg)
                DispatchQueue.main.async { self.state = .failed(error.localizedDescription) }
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self, case .downloading(let version, _) = self.state else { return }
                self.state = .downloading(version: version, progress: progress.fractionCompleted)
            }
        }
        task.resume()
    }
}

private extension Updater.State {
    var hasUpdate: Bool {
        switch self {
        case .available, .downloading, .installing: true
        default: false
        }
    }
}

/// 把 DMG 里的新版 Focus 换到当前 App 的位置上。
enum Installer {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func install(dmg: URL, replacing appURL: URL, newerThan currentVersion: String,
                        bundleID: String? = Bundle.main.bundleIdentifier) throws {
        let mountPoint = try attach(dmg)
        defer { _ = run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet", "-force"]) }

        // 校验：确实是 Focus、版本更新、签名完整
        let newApp = URL(fileURLWithPath: mountPoint).appendingPathComponent("Focus.app")
        guard let bundle = Bundle(url: newApp), bundle.bundleIdentifier == bundleID,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { throw Failure("更新包里没有找到 Focus") }
        guard Updater.isVersion(version, newerThan: currentVersion) else { throw Failure("更新包的版本不比当前新") }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]).status == 0 else {
            throw Failure("更新包签名校验失败")
        }

        // 先复制到旁边，再原子地替换，失败也不会留下半个 App
        let folder = appURL.deletingLastPathComponent()
        let staged = folder.appendingPathComponent(".Focus-update-\(UUID().uuidString).app")
        guard run("/usr/bin/ditto", [newApp.path, staged.path]).status == 0 else {
            throw Failure("没有权限写入「\(folder.lastPathComponent)」文件夹，请手动安装")
        }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        do {
            _ = try FileManager.default.replaceItemAt(appURL, withItemAt: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw Failure("替换旧版本失败：\(error.localizedDescription)")
        }
    }

    /// 等当前进程退出后再打开新版
    static func relaunch(_ appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(appURL.path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func attach(_ dmg: URL) throws -> String {
        let result = run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-plist"])
        guard result.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: result.output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw Failure("无法打开更新包") }
        return mountPoint
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, Data()) }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}
