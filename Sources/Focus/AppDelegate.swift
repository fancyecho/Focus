import AppKit
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FocusStore.shared
    private let overlay = OverlayController()
    private var statusItem: NSStatusItem!
    private var menuPanel: MenuPanelController!
    private var hotKey: HotKey?
    private var hotKeyDown = false
    private var idleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenuPanel)

        menuPanel = MenuPanelController(content: MenuView(
            store: store,
            onStart: { [weak self] in self?.startFromMenu() },
            onQuit: { NSApp.terminate(nil) }))

        // ⌥⌘F：没显示时按一下开启；显示时长按解除
        let hotKey = HotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | optionKey))
        hotKey.onPress = { [weak self] in self?.hotKeyPressed() }
        hotKey.onRelease = { [weak self] in self?.hotKeyReleased() }
        self.hotKey = hotKey

        idleTimer = Timer.scheduledTimer(timeInterval: 5, target: self,
                                         selector: #selector(checkIdle), userInfo: nil, repeats: true)

        if CommandLine.arguments.contains("--show") {
            overlay.show(playSound: true)
        }
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
            overlay.show(playSound: true)
        }
    }

    private func hotKeyReleased() {
        hotKeyDown = false
        overlay.endHold()
    }

    // MARK: 离开检测

    @objc private func checkIdle() {
        guard store.idleMinutes > 0, !overlay.isShowing else { return }
        // 看网课、开会时很久不碰键鼠是正常的，不打断
        let blocker = MediaActivity.appKeepingDisplayAwake()
        if store.autoPausedBy != blocker { store.autoPausedBy = blocker }
        guard blocker == nil else { return }

        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= TimeInterval(store.idleMinutes * 60) {
            // 离开的这段时间也算专注（你在书桌前做题）
            overlay.show(since: Date().addingTimeInterval(-idle), playSound: false)
        }
    }

    // MARK: 菜单栏面板

    @objc private func toggleMenuPanel() {
        guard let button = statusItem.button else { return }
        menuPanel.toggle(below: button)
    }

    private func startFromMenu() {
        menuPanel.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.overlay.show(playSound: true) }
    }
}
