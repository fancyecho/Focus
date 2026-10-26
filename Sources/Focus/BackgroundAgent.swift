import AppKit
import ServiceManagement

/// “防止被强行退出”：把 Focus 交给系统的 launchd 守着。
/// 被活动监视器、强制退出、killall 结束后，launchd 几秒内就把它重新拉起来；
/// 从菜单正常退出（退出码 0）则不会重开。
enum BackgroundAgent {
    static let label = "com.helian.focus.agent"
    private static var service: SMAppService { .agent(plistName: "\(label).plist") }

    static var isEnabled: Bool { service.status == .enabled }
    static var needsApproval: Bool { service.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try service.register() } else { try service.unregister() }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// 这次是不是 launchd 拉起来的
    private static var launchedByAgent: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label
    }

    /// 开了守护、但这次是从访达或更新后直接打开的：请 launchd 接管，自己退出。
    /// 只有确认另一个实例真的起来了才退，免得两边都没在跑
    static func handOffIfNeeded() {
        guard isEnabled, !launchedByAgent else { return }
        let kick = Process()
        kick.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        kick.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
        try? kick.run()
        kick.waitUntilExit()

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.processIdentifier != ownPID }
            if !others.isEmpty { exit(0) }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
