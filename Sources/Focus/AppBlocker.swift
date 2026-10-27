import AppKit
import SwiftUI

/// 盯着所有 App：被时段限制的 App 一律收起来（严格时段直接退出），
/// 切到前台时盖上一层拦截界面。
final class AppBlocker: NSObject {
    private let store = ScheduleStore.shared
    private let shield = ShieldController()
    private let countdown = PassCountdownController()
    private var passTimers: [String: [Timer]] = [:]
    private var timer: Timer?
    /// 最近一次用的、没被限制的 App，“回到学习”时切回去
    private var lastAllowedApp: NSRunningApplication?
    /// 已经请求退出的 App 和请求时间：太久没退就强制退出
    private var quitting: [pid_t: Date] = [:]
    private static let forceQuitAfter: TimeInterval = 15

    /// 专注画面显示时不弹拦截界面（它已经盖住了整个屏幕）
    var isSuspended: () -> Bool = { false }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(evaluate),
                           name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(evaluate),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        // 改了系统时间或时区：马上重新算
        NotificationCenter.default.addObserver(self, selector: #selector(evaluate),
                                               name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(evaluate),
                                               name: .NSSystemTimeZoneDidChange, object: nil)
        timer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(evaluate),
                                     userInfo: nil, repeats: true)

        shield.onBack = { [weak self] in self?.backToStudy() }
        shield.onPass = { [weak self] app, rule in self?.grantPass(to: app, rule: rule) }
        countdown.onEndEarly = { [weak self] bundleID in self?.endPassEarly(bundleID) }
        evaluate()
    }

    /// 专注画面要出来了：先收起拦截界面，被限制的 App 也收起来
    func yieldToOverlay() {
        guard let app = shield.app else { return }
        putAway(app)
        shield.dismiss(playSound: false)
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        check(app)
    }

    @objc private func evaluate() {
        store.pinStrictSessions()
        store.dropExpiredPasses()
        countdown.refresh()
        // 时段结束了，或者拿到了临时放行：收起拦截界面，App 留在前台
        if let shown = shield.app, store.blockingOccurrence(for: shown.bundleIdentifier ?? "") == nil {
            shield.dismiss(playSound: false)
        }
        sweepBackgroundApps()
        if let front = NSWorkspace.shared.frontmostApplication { check(front) }
    }

    private func check(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return }
        guard let occurrence = store.blockingOccurrence(for: bundleID) else {
            lastAllowedApp = app
            // 用 ⌘Tab 切到了一个没被限制的 App：被拦的那个也要收起来，不能留在后面偷看
            if let blocked = shield.app, shield.isShowing {
                putAway(blocked)
                shield.dismiss(playSound: false)
            }
            return
        }
        if isSuspended() {
            putAway(app)
            return
        }
        // 同一个 App 又跳到前台不算新的一次
        let isNewAttempt = !(shield.isShowing && shield.app?.processIdentifier == app.processIdentifier)
        let attempt = isNewAttempt ? store.recordAttempt(for: bundleID) : nil
        shield.show(app: app, occurrence: occurrence, passesLeft: store.passesLeft(for: occurrence.rule), attempt: attempt)
    }

    /// 后台开着的被限制 App：窗口露在后面也能滚动着看，所以统统收起来
    private func sweepBackgroundApps() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        quitting = quitting.filter { pid, _ in NSRunningApplication(processIdentifier: pid) != nil }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
                  app.processIdentifier != front, app.processIdentifier != shield.app?.processIdentifier,
                  store.blockingOccurrence(for: bundleID) != nil
            else { continue }
            putAway(app)
        }
    }

    /// 温和时段收起来；严格时段直接退出（后台放歌、弹消息也一并停掉）
    private func putAway(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, let occurrence = store.blockingOccurrence(for: bundleID) else {
            app.hide()
            return
        }
        guard occurrence.rule.isStrict else {
            if !app.isHidden { app.hide() }
            return
        }
        if let asked = quitting[app.processIdentifier] {
            if Date().timeIntervalSince(asked) > Self.forceQuitAfter { app.forceTerminate() }
        } else {
            quitting[app.processIdentifier] = Date()
            app.hide()
            app.terminate()
        }
    }

    private func backToStudy() {
        if let app = shield.app { putAway(app) }
        shield.dismiss(playSound: true)
        if let lastAllowedApp, !lastAllowedApp.isTerminated { lastAllowedApp.activate() }
    }

    private func grantPass(to app: NSRunningApplication, rule: BlockRule) {
        guard let bundleID = app.bundleIdentifier else { return }
        store.grantPass(for: bundleID, rule: rule)
        shield.dismiss(playSound: false)
        app.activate()
        countdown.refresh()
        schedulePassTimers(for: bundleID)
    }

    /// 剩 1 分钟轻轻提醒一声；到点准时重新检查（不用等下一次 5 秒轮询）
    private func schedulePassTimers(for bundleID: String) {
        passTimers[bundleID]?.forEach { $0.invalidate() }
        guard let end = store.passes[bundleID] else { return }
        let chime = Timer(fire: end.addingTimeInterval(-60), interval: 0, repeats: false) { _ in
            SoundPlayer.shared.playNote(2)
        }
        let expiry = Timer(fire: end.addingTimeInterval(0.2), interval: 0, repeats: false) { [weak self] _ in
            self?.passTimers[bundleID] = nil
            self?.evaluate()
        }
        [chime, expiry].forEach { RunLoop.main.add($0, forMode: .common) }
        passTimers[bundleID] = [chime, expiry]
    }

    /// 倒计时胶囊上点了“现在结束”：收回放行，App 收起来
    private func endPassEarly(_ bundleID: String) {
        passTimers[bundleID]?.forEach { $0.invalidate() }
        passTimers[bundleID] = nil
        store.revokePass(for: bundleID)
        // 后台 App 收不了别人的前台窗口，先借这次点击让 Focus 自己成为活跃 App
        NSApp.activate(ignoringOtherApps: true)
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.hide() }
        SoundPlayer.shared.playNote(5)
        if let lastAllowedApp, !lastAllowedApp.isTerminated { lastAllowedApp.activate() }
        countdown.refresh()
    }
}

/// 拦截界面的窗口：每块屏幕一层模糊，主屏上放内容。
final class ShieldController {
    static let holdSeconds: TimeInterval = 3

    private(set) var app: NSRunningApplication?
    private var model = ShieldModel()
    private var windows: [(window: OverlayWindow, blur: BackdropBlurView)] = []
    private var isDismissing = false

    var onBack: () -> Void = {}
    var onPass: (NSRunningApplication, BlockRule) -> Void = { _, _ in }

    var isShowing: Bool { app != nil && !isDismissing }

    func show(app: NSRunningApplication, occurrence: Occurrence, passesLeft: Int, attempt: Int?) {
        if isShowing, self.app?.processIdentifier == app.processIdentifier {
            // 同一个 App 又跳到前台（比如点了它的通知）：内容更新一下，焦点拿回来
            model.occurrence = occurrence
            model.passesLeft = passesLeft
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.window.makeKeyAndOrderFront(nil)
            return
        }
        if self.app != nil { tearDown() }

        self.app = app
        model = ShieldModel()
        model.appName = app.localizedName ?? "这个 App"
        model.appIcon = app.icon ?? AppIcons.icon(for: app.bundleIdentifier ?? "")
        model.occurrence = occurrence
        model.passesLeft = passesLeft
        model.attempt = attempt ?? 1
        model.onBack = { [weak self] in self?.onBack() }
        model.onHoldChanged = { [weak self] holding in self?.setHolding(holding) }
        model.onHoldCompleted = { [weak self] in
            guard let self, let app = self.app, let rule = self.model.occurrence?.rule else { return }
            SoundPlayer.shared.playNote(4)
            self.onPass(app, rule)
        }

        buildWindows()
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.window.makeKeyAndOrderFront(nil)
        windows.forEach { $0.blur.setBlurred(true, duration: 0.8) }
        SoundPlayer.shared.playNote(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.model.appeared = true }
    }

    func dismiss(playSound: Bool) {
        guard app != nil, !isDismissing else { return }
        isDismissing = true
        if playSound { SoundPlayer.shared.playNote(5) }
        SoundPlayer.shared.stop(.hold, fade: 0.2)
        model.appeared = false
        windows.forEach { $0.blur.setBlurred(false, duration: 0.5) }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            windows.forEach { $0.window.animator().alphaValue = 0 }
        }, completionHandler: {
            self.tearDown()
        })
    }

    private func setHolding(_ holding: Bool) {
        guard isShowing else { return }
        model.holding = holding
        if holding {
            withAnimation(.linear(duration: Self.holdSeconds)) { model.holdProgress = 1 }
            SoundPlayer.shared.play(.hold)
        } else {
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { model.holdProgress = 0 }
            SoundPlayer.shared.stop(.hold, fade: 0.25)
        }
    }

    private func tearDown() {
        windows.forEach { $0.window.orderOut(nil) }
        windows.removeAll()
        app = nil
        isDismissing = false
    }

    private func buildWindows() {
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let screens = NSScreen.screens.filter { $0 == mainScreen } + NSScreen.screens.filter { $0 != mainScreen }
        for screen in screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)

            let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let blur = BackdropBlurView(frame: container.bounds)
            container.addSubview(blur)
            let content = NSHostingView(rootView: ShieldView(model: model, showsContent: screen == mainScreen))
            content.frame = container.bounds
            content.autoresizingMask = [.width, .height]
            container.addSubview(content)

            window.contentView = container
            window.orderFrontRegardless()
            windows.append((window, blur))
        }
    }
}
