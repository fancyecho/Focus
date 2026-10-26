import AppKit
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FocusStore.shared
    private let overlay = OverlayController()
    private let blocker = AppBlocker()
    private let schedulesWindow = SchedulesWindowController()
    private var statusItem: NSStatusItem!
    private var menuPanel: MenuPanelController!
    private var hotKey: HotKey?
    private var hotKeyDown = false
    private var idleTimer: Timer?
    private var lastIdleCheck = Date()
    /// 启动或最近一次醒来的时刻，离开时长不往这之前算
    private var lastWake = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        BackgroundAgent.handOffIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenuPanel)

        menuPanel = MenuPanelController(content: MenuView(
            store: store,
            onStart: { [weak self] in self?.startFromMenu() },
            onOpenSchedules: { [weak self] in self?.openSchedules() },
            onQuit: { NSApp.terminate(nil) }))

        blocker.isSuspended = { [weak self] in self?.overlay.isShowing ?? false }
        blocker.start()

        // ⌥⌘F：没显示时按一下开启；显示时长按解除
        let hotKey = HotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | optionKey))
        hotKey.onPress = { [weak self] in self?.hotKeyPressed() }
        hotKey.onRelease = { [weak self] in self?.hotKeyReleased() }
        self.hotKey = hotKey

        let updater = Updater.shared
        updater.onStateChange = { [weak self] in
            guard let self else { return }
            self.statusItem.button?.image = updater.hasUpdate ? StatusIcon.badgedImage : StatusIcon.image
            DispatchQueue.main.async { self.menuPanel.relayout() }
        }
        updater.start()

        idleTimer = Timer.scheduledTimer(timeInterval: 5, target: self,
                                         selector: #selector(checkIdle), userInfo: nil, repeats: true)

        if CommandLine.arguments.contains("--show") {
            showOverlay(playSound: true)
        }
        if CommandLine.arguments.contains("--schedules") {
            openSchedules()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 更新时要重启，那次放行
        if ScheduleStore.shared.hasStrictRuleActive, !Updater.shared.isRelaunching { return .terminateCancel }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.saveProgress()
    }

    // MARK: 快捷键

    private func hotKeyPressed() {
        guard !hotKeyDown else { return } // 忽略按住时的自动重复
        hotKeyDown = true
        if overlay.isShowing {
            overlay.beginHold()
        } else {
            menuPanel.close()
            showOverlay(playSound: true)
        }
    }

    private func hotKeyReleased() {
        hotKeyDown = false
        overlay.endHold()
    }

    // MARK: 离开检测

    @objc private func checkIdle() {
        // 合盖后 Mac 会周期性“半醒”，屏幕不亮，也不会发系统通知；
        // 这时不能检测离开，否则会在黑屏里开始专注，并把合盖前的时间都算进去
        let now = Date()
        if now.timeIntervalSince(lastIdleCheck) > OverlayController.sleepGap { lastWake = now }
        lastIdleCheck = now
        if Displays.areAsleep { lastWake = now }

        guard store.idleMinutes > 0, !overlay.isShowing, now > lastWake else { return }
        // 看网课、开会时很久不碰键鼠是正常的，不打断
        let blocker = MediaActivity.appKeepingDisplayAwake()
        if store.autoPausedBy != blocker { store.autoPausedBy = blocker }
        guard blocker == nil else { return }

        let anyInput = CGEventType(rawValue: ~0)!
        let threshold = TimeInterval(store.idleMinutes * 60)
        let idle = min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput),
                       now.timeIntervalSince(lastWake))
        if idle >= threshold {
            // 离开的这段时间也算专注（你在书桌前做题），但最多往回算一个离开时长
            showOverlay(since: now.addingTimeInterval(-min(idle, threshold + 10)), playSound: false)
        }
    }

    // MARK: 菜单栏面板

    @objc private func toggleMenuPanel() {
        guard let button = statusItem.button else { return }
        store.refreshBackgroundStatus()
        menuPanel.toggle(below: button)
    }

    private func startFromMenu() {
        menuPanel.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.showOverlay(playSound: true) }
    }

    private func openSchedules() {
        menuPanel.close()
        schedulesWindow.show()
    }

    /// 专注画面会盖住整个屏幕，拦截界面先让开
    private func showOverlay(since start: Date = Date(), playSound: Bool) {
        blocker.yieldToOverlay()
        overlay.show(since: start, playSound: playSound)
    }
}
