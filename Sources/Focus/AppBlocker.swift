import AppKit
import SwiftUI

/// 被拦下的东西：一个 App，或者浏览器里的一个网站
enum BlockTarget {
    case app(NSRunningApplication)
    case site(BlockedSite, browser: NSRunningApplication)

    /// 临时放行、拦截计数用的键
    var passKey: String {
        switch self {
        case .app(let app): app.bundleIdentifier ?? ""
        case .site(let site, _): site.passKey
        }
    }

    /// 判断“是不是同一个”：同一个 App 进程，或者同一个浏览器里的同一个网站
    var identity: String {
        switch self {
        case .app(let app): "app:\(app.processIdentifier)"
        case .site(let site, let browser): "site:\(site.pattern):\(browser.processIdentifier)"
        }
    }

    var name: String {
        switch self {
        case .app(let app): app.localizedName ?? "这个 App"
        case .site(let site, _): site.displayName
        }
    }

    var icon: NSImage {
        switch self {
        case .app(let app): app.icon ?? AppIcons.icon(for: app.bundleIdentifier ?? "")
        case .site(let site, _): SiteIcons.shared.icon(for: site)
        }
    }

    var isSite: Bool {
        if case .site = self { return true }
        return false
    }
}

/// 盯着所有 App 和浏览器：被时段限制的 App 一律收起来（严格时段直接退出），
/// 切到前台、或者浏览器停在被暂停的网站上时，盖上一层拦截界面。
final class AppBlocker: NSObject {
    private let store = ScheduleStore.shared
    private let access = BrowserAccess.shared
    private let shield = ShieldController()
    private let countdown = PassCountdownController()
    private var passTimers: [String: [Timer]] = [:]
    private var timer: Timer?
    private var webTimer: Timer?
    /// 最近一次用的、没被限制的 App，“回到学习”时切回去
    private var lastAllowedApp: NSRunningApplication?
    /// 已经请求退出的 App 和请求时间：太久没退就强制退出
    private var quitting: [pid_t: Date] = [:]
    private static let forceQuitAfter: TimeInterval = 15
    /// 浏览器在前台时多久读一次网址
    private static let webInterval: TimeInterval = 0.8

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
        webTimer = Timer.scheduledTimer(timeInterval: Self.webInterval, target: self, selector: #selector(checkBrowser),
                                        userInfo: nil, repeats: true)

        shield.onBack = { [weak self] in self?.backToStudy() }
        shield.onPass = { [weak self] target, rule in self?.grantPass(to: target, rule: rule) }
        countdown.onEndEarly = { [weak self] key in self?.endPassEarly(key) }
        evaluate()
    }

    /// 专注画面要出来了：先收起拦截界面，被拦的 App 收起来、网站标签页关掉
    func yieldToOverlay() {
        guard let target = shield.target else { return }
        putAway(target)
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
        // 时段结束了，或者拿到了临时放行：收起拦截界面，App / 网页留在前台
        if let shown = shield.target, !isStillBlocked(shown) {
            shield.dismiss(playSound: false)
        }
        sweepBackgroundApps()
        sweepStrictTabs()
        if let front = NSWorkspace.shared.frontmostApplication { check(front) }
    }

    private func isStillBlocked(_ target: BlockTarget) -> Bool {
        switch target {
        case .app(let app): store.blockingOccurrence(for: app.bundleIdentifier ?? "") != nil
        case .site(let site, _): store.isBlocking(site: site)
        }
    }

    // MARK: App

    private func check(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return }
        guard let occurrence = store.blockingOccurrence(for: bundleID) else {
            lastAllowedApp = app
            if let shown = shield.target, shield.isShowing {
                // 拦着网站时又切回同一个浏览器：马上再看一眼网址，还是那个网站就继续拦
                if case .site(_, let browser) = shown, browser.processIdentifier == app.processIdentifier {
                    checkBrowser()
                    return
                }
                // 用 ⌘Tab 切到了别的 App：被拦的那个也要收起来，不能留在后面偷看
                putAway(shown)
                shield.dismiss(playSound: false)
            }
            return
        }
        if isSuspended() {
            putAway(.app(app))
            return
        }
        present(.app(app), occurrence: occurrence)
    }

    private func present(_ target: BlockTarget, occurrence: Occurrence) {
        // 同一个东西又跳到前台不算新的一次
        let isNewAttempt = !(shield.isShowing && shield.target?.identity == target.identity)
        let attempt = isNewAttempt ? store.recordAttempt(for: target.passKey) : nil
        shield.show(target, occurrence: occurrence, passesLeft: store.passesLeft(for: occurrence.rule), attempt: attempt)
    }

    /// 后台开着的被限制 App：窗口露在后面也能滚动着看，所以统统收起来
    private func sweepBackgroundApps() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        quitting = quitting.filter { pid, _ in NSRunningApplication(processIdentifier: pid) != nil }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
                  app.processIdentifier != front, shield.target?.identity != "app:\(app.processIdentifier)",
                  store.blockingOccurrence(for: bundleID) != nil
            else { continue }
            putAway(.app(app))
        }
    }

    /// 温和：App 收起来、网站关掉标签页；严格：App 直接退出（后台放歌、弹消息也一并停掉）
    private func putAway(_ target: BlockTarget) {
        switch target {
        case .site(_, let browser):
            Browser.from(bundleID: browser.bundleIdentifier)?.closeFrontTab()
        case .app(let app):
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
    }

    // MARK: 网站

    /// 浏览器在前台、又有包含网站的时段在生效时，读一下当前标签页的网址
    @objc private func checkBrowser() {
        guard !isSuspended(), !store.activeSiteOccurrences().isEmpty,
              let front = NSWorkspace.shared.frontmostApplication,
              let browser = Browser.from(bundleID: front.bundleIdentifier),
              access.isGranted(browser),
              let url = browser.frontURL()
        else { return }
        guard let (occurrence, site) = store.blockingSite(for: url) else { return }
        present(.site(site, browser: front), occurrence: occurrence)
    }

    /// 严格时段：所有浏览器里匹配的标签页都关掉，后台放着的视频也不行。
    /// 拦截界面正盖着的那个标签页先留着，等“回到学习”时再关
    private func sweepStrictTabs() {
        let strictSites = store.activeSiteOccurrences().filter(\.rule.isStrict).flatMap(\.rule.sites)
        guard !strictSites.isEmpty else { return }
        let shownBrowser: pid_t? = {
            if case .site(_, let browser) = shield.target { return browser.processIdentifier }
            return nil
        }()
        for browser in Browser.allCases where browser.isRunning && access.isGranted(browser) {
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first?.processIdentifier
            browser.closeTabs(where: { url in strictSites.contains { $0.matches(url) } },
                              keepFront: pid != nil && pid == shownBrowser)
        }
    }

    // MARK: 回到学习、临时放行

    private func backToStudy() {
        guard let target = shield.target else { return }
        putAway(target)
        shield.dismiss(playSound: true)
        switch target {
        case .app:
            if let lastAllowedApp, !lastAllowedApp.isTerminated { lastAllowedApp.activate() }
        case .site(_, let browser):
            // 标签页关掉了，留在浏览器里继续（多半是在查资料）
            browser.activate()
        }
    }

    private func grantPass(to target: BlockTarget, rule: BlockRule) {
        store.grantPass(for: target.passKey, rule: rule)
        shield.dismiss(playSound: false)
        switch target {
        case .app(let app): app.activate()
        case .site(_, let browser): browser.activate()
        }
        countdown.refresh()
        schedulePassTimers(for: target.passKey)
    }

    /// 剩 1 分钟轻轻提醒一声；到点准时重新检查（不用等下一次 5 秒轮询）
    private func schedulePassTimers(for key: String) {
        passTimers[key]?.forEach { $0.invalidate() }
        guard let end = store.passes[key] else { return }
        let chime = Timer(fire: end.addingTimeInterval(-60), interval: 0, repeats: false) { _ in
            SoundPlayer.shared.playNote(2)
        }
        let expiry = Timer(fire: end.addingTimeInterval(0.2), interval: 0, repeats: false) { [weak self] _ in
            self?.passTimers[key] = nil
            self?.evaluate()
            self?.checkBrowser()
        }
        [chime, expiry].forEach { RunLoop.main.add($0, forMode: .common) }
        passTimers[key] = [chime, expiry]
    }

    /// 倒计时胶囊上点了“现在结束”：收回放行，App 收起来 / 网站标签页关掉
    private func endPassEarly(_ key: String) {
        passTimers[key]?.forEach { $0.invalidate() }
        passTimers[key] = nil
        store.revokePass(for: key)
        // 后台 App 收不了别人的前台窗口，先借这次点击让 Focus 自己成为活跃 App
        NSApp.activate(ignoringOtherApps: true)
        if key.hasPrefix(BlockedSite.passPrefix) {
            let pattern = String(key.dropFirst(BlockedSite.passPrefix.count))
            let site = BlockedSite(pattern: pattern, name: nil)
            for browser in Browser.allCases where browser.isRunning && access.isGranted(browser) {
                if let url = browser.frontURL(), site.matches(url) { browser.closeFrontTab() }
            }
        } else {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: key) { app.hide() }
        }
        SoundPlayer.shared.playNote(5)
        if let lastAllowedApp, !lastAllowedApp.isTerminated { lastAllowedApp.activate() }
        countdown.refresh()
    }
}

/// 拦截界面的窗口：每块屏幕一层模糊，主屏上放内容。
final class ShieldController {
    static let holdSeconds: TimeInterval = 3

    private(set) var target: BlockTarget?
    private var model = ShieldModel()
    private var windows: [(window: OverlayWindow, blur: BackdropBlurView)] = []
    private var isDismissing = false

    var onBack: () -> Void = {}
    var onPass: (BlockTarget, BlockRule) -> Void = { _, _ in }

    var isShowing: Bool { target != nil && !isDismissing }

    func show(_ target: BlockTarget, occurrence: Occurrence, passesLeft: Int, attempt: Int?) {
        if isShowing, self.target?.identity == target.identity {
            // 同一个东西又跳到前台（比如点了它的通知）：内容更新一下，焦点拿回来
            model.occurrence = occurrence
            model.passesLeft = passesLeft
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.window.makeKeyAndOrderFront(nil)
            return
        }
        if self.target != nil { tearDown() }

        self.target = target
        model = ShieldModel()
        model.appName = target.name
        model.appIcon = target.icon
        model.isSite = target.isSite
        model.occurrence = occurrence
        model.passesLeft = passesLeft
        model.attempt = attempt ?? 1
        model.onBack = { [weak self] in self?.onBack() }
        model.onHoldChanged = { [weak self] holding in self?.setHolding(holding) }
        model.onHoldCompleted = { [weak self] in
            guard let self, let target = self.target, let rule = self.model.occurrence?.rule else { return }
            SoundPlayer.shared.playNote(4)
            self.onPass(target, rule)
        }

        buildWindows()
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.window.makeKeyAndOrderFront(nil)
        windows.forEach { $0.blur.setBlurred(true, duration: 0.8) }
        SoundPlayer.shared.playNote(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.model.appeared = true }
    }

    func dismiss(playSound: Bool) {
        guard target != nil, !isDismissing else { return }
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
        target = nil
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
