import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 点菜单栏图标弹出的玻璃卡片。用自己的面板代替 NSPopover，
/// 才能让它悬浮在菜单栏下方、留出一点空隙，而不是贴着甚至盖住菜单栏。
final class MenuPanelController: NSObject, NSWindowDelegate {
    private static let gap: CGFloat = 6
    private static let screenMargin: CGFloat = 8
    private static let cornerRadius: CGFloat = 22

    private let panel: FloatingPanel
    private let hosting: NSHostingView<AnyView>
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var isClosing = false

    var isShown: Bool { panel.isVisible && !isClosing }

    init<Content: View>(content: Content) {
        hosting = NSHostingView(rootView: AnyView(content))
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        // 外面再包一层圆角遮罩：透明窗口的阴影按内容的形状计算，
        // 不裁成圆角的话，四角会露出方形的阴影边
        let glass = NSGlassEffectView()
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = hosting
        glass.autoresizingMask = [.width, .height]

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.addSubview(glass)
        panel.contentView = container
    }

    func toggle(below button: NSStatusBarButton) {
        isShown ? close() : show(below: button)
    }

    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window, let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let size = hosting.fittingSize
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame // 已经扣掉了菜单栏

        let x = min(max(anchor.midX - size.width / 2, visible.minX + Self.screenMargin),
                    visible.maxX - size.width - Self.screenMargin)
        let top = min(anchor.minY, visible.maxY) - Self.gap
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)

        isClosing = false
        panel.setFrame(frame.offsetBy(dx: 0, dy: 8), display: true)
        panel.contentView?.subviews.first?.frame = NSRect(origin: .zero, size: size)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: {
            self.panel.invalidateShadow() // 内容画好后按圆角重新算一次阴影
        })
        installMonitors()
    }

    /// 内容高度变了（比如出现更新提示），保持顶边不动重新排一下
    func relayout() {
        guard isShown else { return }
        let size = hosting.fittingSize
        guard size != panel.frame.size else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: true)
        panel.contentView?.subviews.first?.frame = NSRect(origin: .zero, size: size)
        panel.invalidateShadow()
    }

    func close() {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 0
            panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: 4), display: true)
        }, completionHandler: {
            self.panel.orderOut(nil)
            self.isClosing = false
        })
    }

    // 点到别的 App 时，面板失去焦点就收起来
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func installMonitors() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShown, event.keyCode == 53 else { return event } // Esc
            self.close()
            return nil
        }
    }

    private func removeMonitors() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        clickMonitor = nil
        keyMonitor = nil
    }
}
