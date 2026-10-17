import AppKit

/// 菜单栏图标：一盏青灯。细长的灯焰（焰尖向右轻挑）+ 实心焰心 + 一弯灯盏。
/// 画成模板图，菜单栏深浅色会自动适配。
enum StatusIcon {
    static let image = make(badge: false)
    /// 右上角带小圆点：有新版本可以更新
    static let badgedImage = make(badge: true)

    private static func make(badge: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineJoin(.round)

            ctx.addPath(flame(bottom: 5.0, top: 17.4, half: 3.9))
            ctx.setLineWidth(1.35)
            ctx.strokePath()

            ctx.addPath(core(bottom: 6.6, top: 11.6, half: 1.6))
            ctx.fillPath()

            ctx.addPath(dish())
            ctx.fillPath()

            if badge {
                // 先挖出一圈空隙，再画圆点，和火焰分开
                let dot = CGRect(x: 13.4, y: 12.8, width: 4.4, height: 4.4)
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: dot.insetBy(dx: -1.2, dy: -1.2))
                ctx.setBlendMode(.normal)
                ctx.fillEllipse(in: dot)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badge ? "Focus（有新版本）" : "Focus"
        return image
    }

    private static let cx: CGFloat = 9

    private static func flame(bottom b: CGFloat, top t: CGFloat, half w: CGFloat) -> CGPath {
        let h = t - b
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx, y: b))
        p.addCurve(to: CGPoint(x: cx + w, y: b + h * 0.36),
                   control1: CGPoint(x: cx + w * 0.62, y: b), control2: CGPoint(x: cx + w, y: b + h * 0.15))
        p.addCurve(to: CGPoint(x: cx + w * 0.22, y: b + h * 0.82),
                   control1: CGPoint(x: cx + w, y: b + h * 0.58), control2: CGPoint(x: cx + w * 0.42, y: b + h * 0.68))
        p.addCurve(to: CGPoint(x: cx + w * 0.55, y: t),
                   control1: CGPoint(x: cx + w * 0.05, y: b + h * 0.92), control2: CGPoint(x: cx + w * 0.2, y: b + h * 0.98))
        p.addCurve(to: CGPoint(x: cx - w, y: b + h * 0.38),
                   control1: CGPoint(x: cx - w * 0.55, y: b + h * 0.88), control2: CGPoint(x: cx - w, y: b + h * 0.62))
        p.addCurve(to: CGPoint(x: cx, y: b),
                   control1: CGPoint(x: cx - w, y: b + h * 0.15), control2: CGPoint(x: cx - w * 0.62, y: b))
        p.closeSubpath()
        return p
    }

    private static func core(bottom b: CGFloat, top t: CGFloat, half w: CGFloat) -> CGPath {
        let h = t - b
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx + 0.15, y: t))
        p.addCurve(to: CGPoint(x: cx + w, y: b + h * 0.32),
                   control1: CGPoint(x: cx + w * 0.7, y: t - h * 0.3), control2: CGPoint(x: cx + w, y: b + h * 0.55))
        p.addCurve(to: CGPoint(x: cx, y: b),
                   control1: CGPoint(x: cx + w, y: b + h * 0.12), control2: CGPoint(x: cx + w * 0.55, y: b))
        p.addCurve(to: CGPoint(x: cx - w, y: b + h * 0.32),
                   control1: CGPoint(x: cx - w * 0.55, y: b), control2: CGPoint(x: cx - w, y: b + h * 0.12))
        p.addCurve(to: CGPoint(x: cx + 0.15, y: t),
                   control1: CGPoint(x: cx - w, y: b + h * 0.55), control2: CGPoint(x: cx - w * 0.5, y: t - h * 0.3))
        p.closeSubpath()
        return p
    }

    private static func dish() -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 3.2, y: 3.4))
        p.addLine(to: CGPoint(x: 14.8, y: 3.4))
        p.addCurve(to: CGPoint(x: 9, y: 0.6), control1: CGPoint(x: 14.2, y: 1.6), control2: CGPoint(x: 11.8, y: 0.6))
        p.addCurve(to: CGPoint(x: 3.2, y: 3.4), control1: CGPoint(x: 6.2, y: 0.6), control2: CGPoint(x: 3.8, y: 1.6))
        p.closeSubpath()
        return p
    }
}
