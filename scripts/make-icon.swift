// 生成 App 图标：夜色里一盏青灯。暖光把周围晕开，像模糊掉的屏幕上唯一清晰的焦点。
// 用法：swift scripts/make-icon.swift <输出.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: stops.map { color($0.0, $0.1) } as CFArray,
               locations: stops.map { $0.2 })!
}

func glow(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
    ctx.drawRadialGradient(gradient([(hex, alpha, 0), (hex, 0, 1)]), startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: radius, options: [])
}

// 和菜单栏图标同一套造型（18×18 设计稿），放大到图标尺寸
let unit: CGFloat = 34
let origin = CGPoint(x: 512 - 9 * unit, y: 214)
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * unit, y: origin.y + y * unit) }

func lampFlame(bottom b: CGFloat, top t: CGFloat, half w: CGFloat) -> CGPath {
    let h = t - b, cx: CGFloat = 9
    let p = CGMutablePath()
    p.move(to: pt(cx, b))
    p.addCurve(to: pt(cx + w, b + h * 0.36), control1: pt(cx + w * 0.62, b), control2: pt(cx + w, b + h * 0.15))
    p.addCurve(to: pt(cx + w * 0.22, b + h * 0.82), control1: pt(cx + w, b + h * 0.58), control2: pt(cx + w * 0.42, b + h * 0.68))
    p.addCurve(to: pt(cx + w * 0.42, t), control1: pt(cx + w * 0.05, b + h * 0.92), control2: pt(cx + w * 0.12, b + h * 0.985))
    p.addCurve(to: pt(cx - w, b + h * 0.38), control1: pt(cx - w * 0.15, t - h * 0.05), control2: pt(cx - w, b + h * 0.64))
    p.addCurve(to: pt(cx, b), control1: pt(cx - w, b + h * 0.15), control2: pt(cx - w * 0.62, b))
    p.closeSubpath()
    return p
}

func dish() -> CGPath {
    let p = CGMutablePath()
    p.move(to: pt(3.2, 3.4))
    p.addLine(to: pt(14.8, 3.4))
    p.addCurve(to: pt(9, 0.6), control1: pt(14.2, 1.6), control2: pt(11.8, 0.6))
    p.addCurve(to: pt(3.2, 3.4), control1: pt(6.2, 0.6), control2: pt(3.8, 1.6))
    p.closeSubpath()
    return p
}

// macOS 图标网格：824×824 的圆角方块，四周留 100
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

// 夜色底：上方是深靛蓝，下方更暗
ctx.drawLinearGradient(gradient([(0x22245A, 1, 0), (0x121433, 1, 0.55), (0x0A0B1E, 1, 1)]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// 远处几团冷色的光，像被模糊掉的屏幕
glow(CGPoint(x: 210, y: 820), 380, 0x5B6CFF, 0.38)
glow(CGPoint(x: 860, y: 760), 320, 0x9A5BFF, 0.26)
glow(CGPoint(x: 820, y: 180), 300, 0x2FB7C8, 0.16)

// 灯光把周围晕暖
let flameCenter = pt(9, 9.6)
glow(flameCenter, 470, 0xFF9A3D, 0.42)
glow(flameCenter, 250, 0xFFC873, 0.38)
// 灯光落在桌面上
glow(pt(9, 1.6), 300, 0xFFB35A, 0.22)

// 灯盏：温润的铜色，口沿一道油光
ctx.saveGState()
ctx.addPath(dish())
ctx.clip()
ctx.drawLinearGradient(gradient([(0xE0A065, 1, 0), (0x9C5A2C, 1, 0.55), (0x4A2612, 1, 1)]),
                       start: pt(9, 3.4), end: pt(9, 0.6), options: [])
ctx.restoreGState()
ctx.setFillColor(color(0xFFE2B0, 0.85))
ctx.fillEllipse(in: CGRect(x: pt(3.6, 3.4).x, y: pt(0, 3.4).y - 6, width: 11.2 * unit, height: 12))

// 火焰：先铺一层大光晕，再画焰身（白芯 → 暖黄 → 橙红）
let outer = lampFlame(bottom: 4.5, top: 16.4, half: 3.3)

// 灯芯：一小截，把火和灯盏连起来
ctx.setStrokeColor(color(0x2A170C))
ctx.setLineWidth(0.38 * unit)
ctx.setLineCap(.round)
ctx.move(to: pt(9, 3.4))
ctx.addLine(to: pt(9, 5.0))
ctx.strokePath()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 120, color: color(0xFF9A3D, 0.95))
ctx.addPath(outer)
ctx.setFillColor(color(0xFFB04A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(outer)
ctx.clip()
ctx.drawLinearGradient(gradient([(0xFFF8E6, 1, 0), (0xFFE08A, 1, 0.3), (0xFFA44A, 1, 0.68), (0xFF6A3A, 1, 1)]),
                       start: pt(9, 4.5), end: pt(9, 16.4), options: [])
// 焰心：一团柔白的光
glow(pt(9, 7.0), 3.0 * unit, 0xFFFFFF, 0.95)
ctx.restoreGState()

// 顶部一点玻璃般的高光
ctx.drawLinearGradient(gradient([(0xFFFFFF, 0.10, 0), (0xFFFFFF, 0, 1)]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 620), options: [])
ctx.restoreGState()

// 细描边，让图标边缘在浅色背景上也清楚
ctx.addPath(tilePath)
ctx.setStrokeColor(color(0xFFFFFF, 0.10))
ctx.setLineWidth(3)
ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("已生成 \(output)")
