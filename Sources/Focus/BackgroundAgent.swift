import AppKit
import ServiceManagement

/// “防止被强行退出”：把 Focus 交给系统的 launchd 守着。
/// 被活动监视器、强制退出、killall 结束后，launchd 几秒内就把它重新拉起来；
/// 从菜单正常退出（退出码 0）则不会重开。
///
/// 任何时候只应该有一个 Focus 在跑（否则菜单栏会出现两个图标）：
/// - 守护开着时，守护拉起的实例就是“正主”，它一启动就把别的实例关掉；
/// - 不是守护拉起的实例（从访达打开、更新后重开），启动时请守护重启接管，自己退出。
enum BackgroundAgent {
    static let label = "com.helian.focus.agent"
    /// 测试或接班时用：这次启动不交接
    static let skipHandOffArgument = "--skip-handoff"

    private static var service: SMAppService { .agent(plistName: "\(label).plist") }

    static var isEnabled: Bool { service.status == .enabled }
    static var needsApproval: Bool { service.status == .requiresApproval }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// 这次是不是 launchd 拉起来的
    static var launchedByAgent: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label
    }

    private static var otherInstances: [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ownPID }
    }

    // MARK: 启动时

    /// 启动时调用：保证最后只剩一个实例在跑
    static func settleInstances() {
        if launchedByAgent {
            closeOtherInstances()
        } else {
            handOffIfNeeded()
        }
    }

    /// 守护开着、但这次是从访达或更新后打开的：请守护重启（这样跑的一定是新版程序），自己退出。
    /// 只有确认另一个实例真的起来了才退，免得两边都没在跑
    private static func handOffIfNeeded() {
        guard isEnabled, !CommandLine.arguments.contains(skipHandOffArgument) else { return }
        launchctl(["kickstart", "-k", "gui/\(getuid())/\(label)"])
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if !otherInstances.isEmpty { exit(0) }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// 守护拉起的实例：把其他实例关掉，菜单栏只留一个图标。
    /// 严格时段里对方会拒绝正常退出，两秒后强制结束（它不是守护，不会被重开）
    private static func closeOtherInstances() {
        let others = otherInstances
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }
    }

    // MARK: 开关

    /// 打开：注册后 launchd 会立刻拉起守护实例，由它把当前这个关掉。
    /// 守护本身就会在登录时启动，原来的登录项关掉，免得启动两次
    static func enable() throws {
        try service.register()
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
    }

    /// 关闭：注销守护会连带结束守护拉起的实例，所以先启动一个普通实例接班。
    /// 打开守护时关掉了登录项，这里恢复，登录时照样启动
    static func disable() {
        try? SMAppService.mainApp.register()
        guard launchedByAgent else {
            try? service.unregister()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.arguments = [skipHandOffArgument]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                try? service.unregister()
                // 一般注销时 launchd 就结束了这个实例；没结束的话自己退
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
            }
        }
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
