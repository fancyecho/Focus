import AppKit
import SwiftUI

/// 温和时段“再用 5 分钟”的倒计时：屏幕顶部正中的一枚玻璃胶囊。
/// 不抢焦点，透明的地方点下去会穿透到下面的窗口；鼠标移上去可以提前结束。
final class PassCountdownController {
    private static let size = NSSize(width: 440, height: 220)
    private static let topGap: CGFloat = 8

    private let store = ScheduleStore.shared
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    var onEndEarly: (String) -> Void = { _ in }

    /// 有进行中的临时放行就显示，没有就收起
    func refresh() {
        if store.passes.values.contains(where: { $0 > Date() }) { show() } else { hide() }
    }

    private func show() {
        hideWork?.cancel()
        hideWork = nil
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    /// 胶囊自己会先做退场动画，等它播完再把窗口拿掉
    private func hide() {
        guard panel != nil, hideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.hideWork = nil
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PassCountdownView(store: store) { [weak self] bundleID in
            self?.onEndEarly(bundleID)
        })
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2,
                                     y: visible.maxY - Self.topGap - Self.size.height))
    }
}

private struct PassCountdownView: View {
    let store: ScheduleStore
    let onEndEarly: (String) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let live = store.passes
                .filter { $0.value > context.date }
                .sorted { $0.value < $1.value }
            VStack(spacing: 8) {
                ForEach(live, id: \.key) { pass in
                    PassPill(bundleID: pass.key, end: pass.value, now: context.date) {
                        onEndEarly(pass.key)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 4)
            .animation(.spring(duration: 0.55, bounce: 0.3), value: live.map(\.key))
        }
    }
}

private struct PassPill: View {
    let bundleID: String
    let end: Date
    let now: Date
    let onEndEarly: () -> Void

    @State private var hovering = false

    private static let total = TimeInterval(ScheduleStore.passMinutes * 60)
    private static let urgentColor = Color(red: 1.0, green: 0.42, blue: 0.36)

    private var remaining: Int { max(0, Int(end.timeIntervalSince(now).rounded(.up))) }
    private var urgent: Bool { remaining <= 30 }

    /// 放行的是网站时，键是 "web:域名"
    private var site: BlockedSite? {
        guard bundleID.hasPrefix(BlockedSite.passPrefix) else { return nil }
        let pattern = String(bundleID.dropFirst(BlockedSite.passPrefix.count))
        return BlockedSite.suggestions.first { $0.pattern == pattern } ?? BlockedSite(pattern: pattern, name: nil)
    }

    private var icon: NSImage {
        site.map { SiteIcons.shared.icon(for: $0) } ?? AppIcons.icon(for: bundleID)
    }

    private var appName: String {
        if let site { return site.displayName }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? "App"
    }

    var body: some View {
        let fraction = min(Double(remaining) / Self.total, 1)
        // 最后 30 秒：每秒一明一暗，像灯火快要燃尽
        let breathing = urgent && remaining % 2 == 0

        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.14), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(urgent ? AnyShapeStyle(Self.urgentColor) : AnyShapeStyle(Brand.gradient),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: site == nil ? 0 : 4, style: .continuous))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 0) {
                Text(urgent ? "\(appName) · 马上结束" : "\(appName) · 临时使用")
                    .font(.system(size: 10.5, weight: .semibold))
                    .opacity(0.65)
                    .contentTransition(.interpolate)
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? AnyShapeStyle(Self.urgentColor) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.35), value: remaining)
            }
            .fixedSize()

            if hovering {
                Button(action: onEndEarly) {
                    Text("现在结束")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Brand.gradient, in: .capsule)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .transition(.blurReplace.combined(with: ScaleTransition(0.8, anchor: .leading)))
                .accessibilityHint("提前结束这次临时使用，App 会被收起")
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, hovering ? 7 : 16)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: (urgent ? Self.urgentColor : Brand.glow).opacity(breathing ? 0.55 : 0.18),
                radius: breathing ? 16 : 10, y: 3)
        .animation(.easeInOut(duration: 0.9), value: breathing)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(appName) 临时使用，还剩 \(remaining / 60) 分 \(remaining % 60) 秒")
    }
}
