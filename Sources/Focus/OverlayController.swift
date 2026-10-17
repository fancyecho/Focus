import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// 无边框窗口默认不能成为 key window，这里放开，才能在上面输入解锁语句。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 管理所有屏幕上的模糊层。模糊层不会自动消失，只能通过输入解锁语句或长按快捷键解除。
final class OverlayController: NSObject {
    static let unlockPhrase = "我现在要用电脑做正事"
    static let holdSeconds: TimeInterval = 4
    private static let blurInDuration: TimeInterval = 1.2
    private static let blurOutDuration: TimeInterval = 0.9
    private static let summaryDuration: TimeInterval = 2.6
    /// 多久没碰电脑进入环境模式
    private static let ambientDelay: TimeInterval = 8
    /// 环境模式下多久换一句（有人在看时不换，免得打断）
    private static let quoteInterval: TimeInterval = 15 * 60
    /// 长按到底 / 打完整句时，模糊最多揭开到这个程度
    private static let revealedBlur: CGFloat = 0.4
    /// 睡眠（合盖、熄屏）超过这么久，醒来就算新的一段专注
    private static let newSessionAfterSleep: TimeInterval = 30 * 60

    private let store = FocusStore.shared
    private let sound = SoundPlayer.shared
    private var model = OverlayModel()
    private var windows: [(window: OverlayWindow, blur: BackdropBlurView)] = []
    private var ticker: Timer?
    private var holdWorkItem: DispatchWorkItem?
    private var eventMonitor: Any?
    private var sleepAssertion: IOPMAssertionID = 0
    private var keepAwakeTimer: Timer?
    private var pausedAt: Date?
    private var lastActivity = Date()
    private var lastQuoteChange = Date()
    private var lastMatched = 0

    private(set) var isShowing = false
    private var isExiting = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        // 熄屏和系统睡眠（包括合盖）都要暂停计时，醒来再接着算
        workspace.addObserver(self, selector: #selector(pauseCounting),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(pauseCounting),
                              name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resumeCounting),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resumeCounting),
                              name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// - Parameters:
    ///   - start: 专注从什么时候算起（离开触发时往前算到最后一次操作）
    ///   - playSound: 手动开启时有声音；离开自动触发时静音，免得打扰正在做题的你
    func show(since start: Date = Date(), playSound: Bool) {
        guard !isShowing else { return }
        isShowing = true
        isExiting = false
        lastActivity = Date()
        lastQuoteChange = Date()
        lastMatched = 0
        pausedAt = nil

        model = OverlayModel()
        model.segmentStart = start
        model.onSubmit = { [weak self] in self?.submitTyped() }
        model.onTypedChange = { [weak self] in self?.typedChanged() }

        buildWindows()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                                     .disableHideApplication, .disableAppleMenu]
        primaryWindow?.makeKeyAndOrderFront(nil)

        if playSound { sound.play(.enter) }
        windows.forEach { $0.blur.setBlurred(true, duration: Self.blurInDuration) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.model.appeared = true }

        ticker = Timer.scheduledTimer(timeInterval: 1, target: self,
                                      selector: #selector(tick), userInfo: nil, repeats: true)
        installEventMonitor()
        keepScreenAwake(true)
    }

    // MARK: 长按快捷键解除

    func beginHold() {
        guard isShowing, !isExiting, holdWorkItem == nil else { return }
        noteActivity()
        model.holding = true
        withAnimation(.linear(duration: Self.holdSeconds)) { model.holdProgress = 1 }
        setBlur(Self.revealedBlur, duration: Self.holdSeconds, timing: CAMediaTimingFunction(name: .linear))
        sound.play(.hold)

        let work = DispatchWorkItem { [weak self] in self?.unlock() }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdSeconds, execute: work)
    }

    func endHold() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        guard model.holding, !isExiting else { return }
        model.holding = false
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { model.holdProgress = 0 }
        setBlur(typingBlur, duration: 0.5)
        sound.stop(.hold, fade: 0.25)
    }

    // MARK: 输入语句解除

    /// 输入法拼写中（拼音还没上屏）时，底字要让位，不然会和拼音叠在一起
    private func updateComposing() {
        let editor = primaryWindow?.firstResponder as? NSTextView
        let composing = editor?.hasMarkedText() ?? false
        if model.composing != composing { model.composing = composing }
    }

    /// 每打对一个字：响一个音，模糊再揭开一点
    private func typedChanged() {
        guard isShowing, !isExiting else { return }
        updateComposing()
        let matched = model.matchedCount
        if matched > lastMatched {
            for (step, index) in (lastMatched..<matched).enumerated() {
                sound.playNote(index, delay: Double(step) * 0.07)
            }
        }
        if matched != lastMatched, !model.holding {
            setBlur(blur(forMatched: matched), duration: 0.45)
        }
        lastMatched = matched

        // 打完整句不用按回车，直接解锁
        if OverlayModel.normalize(model.typed) == Self.unlockPhrase {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.unlock() }
        }
    }

    private func submitTyped() {
        guard OverlayModel.normalize(model.typed) != Self.unlockPhrase else { return } // 已在 typedChanged 里解锁
        model.wrongAttempts += 1
        sound.play(.wrong)
        withAnimation(.smooth) { model.typed = "" }
    }

    private var typingBlur: CGFloat { blur(forMatched: model.matchedCount) }

    private func blur(forMatched matched: Int) -> CGFloat {
        let fraction = CGFloat(matched) / CGFloat(Self.unlockPhrase.count)
        return 1 - (1 - Self.revealedBlur) * fraction
    }

    // MARK: 环境模式

    private func installEventMonitor() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.isShowing, !self.isExiting else { return event }
            self.noteActivity()
            guard event.type == .keyDown else { return event }

            if event.keyCode == 53 { // Esc：收起输入框
                withAnimation(.smooth) {
                    self.model.typingRevealed = false
                    self.model.typed = ""
                }
                return nil
            }
            // 输入框一直有焦点，只是没打字时收起来；一打字就展开
            if !self.model.typingRevealed {
                withAnimation(.smooth(duration: 0.55)) { self.model.typingRevealed = true }
            }
            DispatchQueue.main.async { self.updateComposing() }
            return event
        }
    }

    func noteActivity() {
        lastActivity = Date()
        if isShowing, !isExiting { extendKeepAwake() }
        guard model.ambient else { return }
        withAnimation(.smooth(duration: 0.7)) { model.ambient = false }
    }

    @objc private func tick() {
        guard isShowing, !isExiting else { return }
        let idle = Date().timeIntervalSince(lastActivity)

        if !model.ambient, !model.holding, idle >= Self.ambientDelay {
            // 打到一半就离开了：清掉没打完的字，模糊恢复完整
            withAnimation(.easeInOut(duration: 1.8)) {
                model.ambient = true
                model.typingRevealed = false
                model.typed = ""
            }
            NSCursor.setHiddenUntilMouseMoves(true)
        }

        if model.ambient, Date().timeIntervalSince(lastQuoteChange) >= Self.quoteInterval {
            lastQuoteChange = Date()
            withAnimation(.easeInOut(duration: 2.5)) {
                model.quote = Quotes.random(excluding: model.quote)
            }
        }
    }

    // MARK: 退出

    private func unlock() {
        guard isShowing, !isExiting else { return }
        isExiting = true
        holdWorkItem?.cancel()
        holdWorkItem = nil
        ticker?.invalidate()
        ticker = nil
        removeEventMonitor()

        let session = model.elapsed()
        store.record(session)
        model.segmentStart = nil
        model.accumulated = session

        sound.play(.unlock)
        setBlur(Self.revealedBlur, duration: 0.6)
        withAnimation(.smooth(duration: 0.7)) {
            model.ambient = false
            model.holding = false
            model.holdProgress = 0
            model.typingRevealed = false
            model.summary = .init(session: session, today: store.todaySeconds, streak: store.streakDays)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.summaryDuration) { self.fadeOut() }
    }

    private func fadeOut() {
        model.appeared = false
        windows.forEach { $0.blur.setBlurred(false, duration: Self.blurOutDuration) }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.blurOutDuration
            windows.forEach { $0.window.animator().alphaValue = 0 }
        }, completionHandler: {
            self.tearDown()
        })
    }

    private func tearDown() {
        NSApp.presentationOptions = []
        windows.forEach { $0.window.orderOut(nil) }
        windows.removeAll()
        keepScreenAwake(false)
        isShowing = false
        isExiting = false
    }

    /// App 退出时把正在进行的专注记下来
    func saveProgress() {
        guard isShowing, !isExiting else { return }
        store.record(model.elapsed())
    }

    // MARK: 窗口

    private var primaryWindow: OverlayWindow? { windows.first?.window }

    private func setBlur(_ amount: CGFloat, duration: TimeInterval,
                         timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeOut)) {
        windows.forEach { $0.blur.setBlur(amount, duration: duration, timing: timing) }
    }

    private func buildWindows() {
        windows.forEach { $0.window.orderOut(nil) }
        windows.removeAll()

        // 主屏放第一个，它的窗口负责接收输入
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let screens = NSScreen.screens.filter { $0 == mainScreen } + NSScreen.screens.filter { $0 != mainScreen }
        for screen in screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.appearance = NSAppearance(named: .darkAqua)

            let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let blur = BackdropBlurView(frame: container.bounds)
            container.addSubview(blur)

            let content = NSHostingView(rootView: OverlayView(model: model, showsControls: screen == mainScreen))
            content.frame = container.bounds
            content.autoresizingMask = [.width, .height]
            container.addSubview(content)

            window.contentView = container
            window.orderFrontRegardless()
            windows.append((window, blur))
        }
    }

    @objc private func screensChanged() {
        guard isShowing, !isExiting else { return }
        buildWindows()
        setBlur(typingBlur, duration: 0.01)
        primaryWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: 睡眠

    /// 熄屏或系统睡眠（包括合盖）就暂停计时
    @objc private func pauseCounting() {
        guard isShowing, !isExiting else { return }
        keepScreenAwake(false)
        guard let start = model.segmentStart else { return }
        model.accumulated += Date().timeIntervalSince(start)
        model.segmentStart = nil
        pausedAt = Date()
    }

    /// 醒来接着算。睡得太久（比如合盖过夜）就先把之前的记下来，重新开始一段，
    /// 免得醒来看到“专注了 9 小时”
    @objc private func resumeCounting() {
        guard isShowing, !isExiting, model.segmentStart == nil else { return }
        if let pausedAt, Date().timeIntervalSince(pausedAt) >= Self.newSessionAfterSleep {
            store.record(model.accumulated)
            model.accumulated = 0
        }
        pausedAt = nil
        model.segmentStart = Date()
        lastActivity = Date()
        keepScreenAwake(true)
    }

    /// 有人在看就保持亮屏：从最后一次碰电脑算起，超过设定时长没人碰，
    /// 就交还给系统，按系统设置正常熄屏、睡眠。电量低于 20% 时不强制亮屏。
    private func keepScreenAwake(_ awake: Bool) {
        keepAwakeTimer?.invalidate()
        keepAwakeTimer = nil
        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
        let limit = TimeInterval(store.keepAwakeMinutes * 60)
        guard awake, limit > 0, !Battery.isLow else { return }
        IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Focus 正在显示专注画面" as CFString, &sleepAssertion)
        keepAwakeTimer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in
            self?.keepScreenAwake(false)
        }
    }

    /// 碰了电脑：常亮时长从现在重新算（已经放手的话重新接管）
    private func extendKeepAwake() {
        if let keepAwakeTimer, sleepAssertion != 0 {
            keepAwakeTimer.fireDate = Date().addingTimeInterval(TimeInterval(store.keepAwakeMinutes * 60))
        } else {
            keepScreenAwake(true)
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
}
