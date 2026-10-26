import AppKit
import SwiftUI

/// 所有屏幕共享的模糊层状态，由 OverlayController 驱动。
@Observable
final class OverlayModel {
    var appeared = false
    var quote = Quotes.random()

    /// 一段时间没碰电脑就进入环境模式：只留语句和计时，其余都隐去
    var ambient = false

    /// 本次专注已累计的秒数（屏幕睡眠前的部分）+ 当前这段的开始时间
    var accumulated: TimeInterval = 0
    var segmentStart: Date? = Date()

    var holding = false
    var holdProgress: Double = 0

    var typingRevealed = false
    var typed = ""
    var wrongAttempts = 0
    /// 输入法正在拼写（拼音还没上屏）
    var composing = false
    /// 鼠标停在时钟上：时钟翻成专注计时
    var hoveringClock = false

    /// 解锁后的小结，非 nil 时中间内容换成小结
    var summary: Summary?

    var onSubmit: () -> Void = {}
    var onTypedChange: () -> Void = {}

    struct Summary {
        let session: TimeInterval
        let today: TimeInterval
        let streak: Int
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (segmentStart.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// 已经打对的字数（忽略空格和标点），用来点亮提示语
    var matchedCount: Int {
        let phrase = Array(OverlayController.unlockPhrase)
        var count = 0
        for char in Self.normalize(typed) {
            guard count < phrase.count, phrase[count] == char else { break }
            count += 1
        }
        return count
    }

    static func normalize(_ text: String) -> String {
        let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { !ignored.contains($0) }))
    }
}

// MARK: - 模糊层内容

struct OverlayView: View {
    @Bindable var model: OverlayModel
    let showsControls: Bool

    var body: some View {
        ZStack {
            Atmosphere()
                .opacity(model.appeared ? 1 : 0)
                .animation(.easeInOut(duration: model.appeared ? 1.4 : 0.6), value: model.appeared)

            VStack(spacing: 0) {
                Spacer(minLength: 80)

                ZStack {
                    if let summary = model.summary {
                        SummaryView(summary: summary)
                            .transition(.blurReplace.combined(with: ScaleTransition(0.97)))
                    } else {
                        focusContent
                            .transition(.blurReplace.combined(with: ScaleTransition(1.03)))
                    }
                }
                .reveal(model.appeared, delay: 0)

                Spacer(minLength: 40)

                if showsControls {
                    UnlockControls(model: model)
                        .opacity(model.ambient ? 0 : 1)
                        .blur(radius: model.ambient ? 6 : 0)
                        .allowsHitTesting(!model.ambient)
                        .reveal(model.appeared && model.summary == nil, delay: 1.5)
                        .padding(.bottom, 44)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.22), radius: 24, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusContent: some View {
        VStack(spacing: 0) {
            QuoteView(quote: model.quote)
                .id(model.quote.text)
                .transition(.blurReplace)
                .reveal(model.appeared, delay: 0.75)

            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: model.appeared ? 48 : 0, height: 1.5)
                .animation(.smooth(duration: 1.1).delay(model.appeared ? 1.15 : 0), value: model.appeared)
                .padding(.top, 40)
                .padding(.bottom, 34)

            HeroClock(model: model)
                .reveal(model.appeared, delay: 1.25)
        }
    }
}

/// 中文用宋体、英文用 New York 衬线体，比无衬线体更有书卷气
private struct QuoteView: View {
    let quote: Quote

    private var isChinese: Bool { quote.text.unicodeScalars.contains { $0.properties.isIdeographic } }

    var body: some View {
        VStack(spacing: 22) {
            Text(quote.text)
                .font(isChinese ? .custom("STSongti-SC-Bold", size: 48) : .system(size: 46, weight: .semibold, design: .serif))
                .tracking(isChinese ? 2 : 0)
                .lineSpacing(isChinese ? 16 : 10)
                .multilineTextAlignment(.center)
                .frame(maxWidth: isChinese ? 1000 : 960)
                .fixedSize(horizontal: false, vertical: true)

            Text(isChinese ? quote.author : quote.author.uppercased())
                .font(.system(size: isChinese ? 15 : 12, weight: .medium))
                .tracking(isChinese ? 6 : 3)
                .opacity(0.6)
        }
    }
}

/// 中间的大时钟。平时显示当前时间，不让人盯着专注时长；
/// 动一下鼠标，下面的小字换成“已专注 N 分钟”；鼠标停在时钟上，才翻成带秒的专注计时。
private struct HeroClock: View {
    @Bindable var model: OverlayModel

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let showElapsed = model.hoveringClock && !model.ambient
            let elapsed = Int(model.elapsed(at: context.date))
            let clock = Self.time.string(from: context.date)

            VStack(spacing: 14) {
                ZStack {
                    if showElapsed {
                        Text(DurationText.clock(TimeInterval(elapsed)))
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.4), value: elapsed)
                            .transition(.blurReplace)
                    } else {
                        Text(clock)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.8), value: clock)
                            .transition(.blurReplace)
                    }
                }
                .font(.system(size: 92, weight: .thin))
                .monospacedDigit()
                .frame(height: 100)

                ZStack {
                    Text(caption(showElapsed: showElapsed, elapsed: elapsed, date: context.date))
                        .id(captionKind(showElapsed: showElapsed))
                        .transition(.blurReplace)
                }
                .font(.system(size: 13, weight: .semibold))
                .tracking(3)
                .opacity(0.55)
            }
            .padding(.horizontal, 40)
            .contentShape(Rectangle())
        }
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.5)) { model.hoveringClock = hovering }
        }
    }

    private func captionKind(showElapsed: Bool) -> String {
        showElapsed ? "elapsed" : model.ambient ? "date" : "focused"
    }

    private func caption(showElapsed: Bool, elapsed: Int, date: Date) -> String {
        if model.segmentStart == nil { return "已暂停" }
        if showElapsed { return "本次专注" }
        if model.ambient { return Self.date.string(from: date) }
        return elapsed < 60 ? "刚刚开始专注" : "已专注 \(DurationText.long(TimeInterval(elapsed)))"
    }
}

private struct SummaryView: View {
    let summary: OverlayModel.Summary

    var body: some View {
        VStack(spacing: 0) {
            Label(summary.session >= 60 ? "本次专注" : "欢迎回来", systemImage: "checkmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .tracking(4)
                .opacity(0.65)
                .padding(.bottom, 18)

            if summary.session >= 60 {
                let minutes = Int(summary.session / 60)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if minutes >= 60 {
                        Text("\(minutes / 60)").font(.system(size: 110, weight: .thin))
                        Text("小时").font(.system(size: 26)).opacity(0.7).padding(.trailing, 12)
                    }
                    Text("\(minutes % 60)").font(.system(size: 110, weight: .thin))
                    Text("分钟").font(.system(size: 26)).opacity(0.7)
                }
                .monospacedDigit()

                HStack(spacing: 14) {
                    Text("今日累计 \(DurationText.long(summary.today))")
                    if summary.streak > 1 {
                        Circle().frame(width: 3, height: 3).opacity(0.6)
                        Text("连续专注 \(summary.streak) 天")
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .opacity(0.65)
                .padding(.top, 22)
            } else {
                Text("用完电脑，记得回到书桌前")
                    .font(.custom("STSongti-SC-Bold", size: 40))
                    .tracking(2)
            }
        }
    }
}

// MARK: - 氛围：暗角 + 颗粒

/// 四周压暗把视线引向中央；一层极淡的颗粒让大面积模糊不显得塑料感
struct Atmosphere: View {
    var body: some View {
        GeometryReader { proxy in
            let radius = hypot(proxy.size.width, proxy.size.height) / 2
            ZStack {
                RadialGradient(
                    stops: [
                        .init(color: .black.opacity(0.06), location: 0),
                        .init(color: .black.opacity(0.10), location: 0.45),
                        .init(color: .black.opacity(0.42), location: 1),
                    ],
                    center: .center, startRadius: 0, endRadius: radius)
                Image(nsImage: Grain.image)
                    .resizable(resizingMode: .tile)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private enum Grain {
    static let image: NSImage = {
        let size = 160
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var seed: UInt32 = 0x2545_F491
        for i in 0..<(size * size) {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let light = seed & 1 == 0
            let alpha = UInt8((seed >> 8) % 14) // 0…13 / 255，非常淡
            let value: UInt8 = light ? alpha : 0  // 预乘 alpha
            pixels[i * 4] = value; pixels[i * 4 + 1] = value; pixels[i * 4 + 2] = value
            pixels[i * 4 + 3] = alpha
        }
        let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: size / 2, height: size / 2))
    }()
}

// MARK: - 解锁控件

/// 展开输入框时，长按胶囊的玻璃融进输入框里，而不是单独淡出
private struct UnlockControls: View {
    @Bindable var model: OverlayModel
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if !model.typingRevealed {
                    HoldPill(holding: model.holding, progress: model.holdProgress, glass: glass)
                }
                TypingCapsule(model: model, glass: glass)
            }
        }
        .animation(.smooth(duration: 0.55), value: model.typingRevealed)
    }
}

/// “输入语句解除”胶囊。点开（或直接打字）后原地展开成输入框：
/// 那句话作为淡色底字放在框里，打的字正好盖在底字上，不再单独显示一遍。
private struct TypingCapsule: View {
    @Bindable var model: OverlayModel
    let glass: Namespace.ID
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let font = Font.system(size: 20, weight: .medium)
    private static let phrase = Array(OverlayController.unlockPhrase)
    /// 底字的实际排版宽度（和输入框用同一个字体量出来，保证逐字对齐）
    private static let phraseWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: 20, weight: .medium)
        return ceil((OverlayController.unlockPhrase as NSString).size(withAttributes: [.font: font]).width) + 6
    }()

    private var revealed: Bool { model.typingRevealed }

    var body: some View {
        ZStack(alignment: .leading) {
            // 底字：打对的字由输入框里的真字盖住；输入法拼写中或打错时隐去，免得和拼音叠在一起。
            // 用一整段 Text（而不是逐字拼）排版，字距才和输入框里的完全一样
            Text(ghostText)
                .font(Self.font)
                .fixedSize()
                .allowsHitTesting(false)
                .animation(.smooth(duration: 0.25), value: model.matchedCount)
                .animation(.smooth(duration: 0.25), value: model.composing)

            TextField("", text: $model.typed)
                .textFieldStyle(.plain)
                .font(Self.font)
                .focused($focused)
                .onSubmit { model.onSubmit() }
                .onChange(of: model.typed) { model.onTypedChange() }
                .opacity(revealed ? 1 : 0)

            Label("输入语句解除", systemImage: "keyboard")
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
                .frame(maxWidth: .infinity)
                .opacity(revealed ? 0 : 1)
                .blur(radius: revealed ? 6 : 0)
                .allowsHitTesting(false)
        }
        .frame(width: revealed ? Self.phraseWidth : 104, height: 26)
        .padding(.horizontal, 4) // 留出余量，裁剪时不切到首尾的字
        .clipped()
        .padding(.horizontal, revealed ? 20 : 12)
        .padding(.vertical, revealed ? 12 : 7)
        .contentShape(Capsule())
        .onTapGesture {
            if !revealed { withAnimation(.smooth(duration: 0.55)) { model.typingRevealed = true } }
            focused = true
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("typing", in: glass)
        // 开了“减弱动态效果”就不左右晃，只靠提示音
        .modifier(Shake(attempts: reduceMotion ? 0 : CGFloat(model.wrongAttempts)))
        .animation(.default, value: model.wrongAttempts)
        .animation(.smooth(duration: 0.55), value: revealed)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            focused = true
        }
    }

    private var ghostText: AttributedString {
        var text = AttributedString()
        for (index, char) in Self.phrase.enumerated() {
            var piece = AttributedString(String(char))
            piece.foregroundColor = .white.opacity(ghostOpacity(at: index))
            text += piece
        }
        return text
    }

    private func ghostOpacity(at index: Int) -> Double {
        guard revealed, index >= model.matchedCount else { return 0 }
        let mistyped = model.typed.count > model.matchedCount
        return model.composing || mistyped ? 0 : 0.3
    }
}

/// 长按快捷键的胶囊：按住时从左往右填满，松手会弹回去
private struct HoldPill: View {
    let holding: Bool
    let progress: Double
    let glass: Namespace.ID

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15, height: 15)
            Text(holding ? "继续按住…" : "按住 ⌥⌘F 解除")
                .contentTransition(.interpolate)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .clipShape(Capsule())
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("hold", in: glass)
        .animation(.smooth(duration: 0.3), value: holding)
    }
}

// MARK: - 动画工具

struct Reveal: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // 开了“减弱动态效果”就只淡入淡出，不位移、不变模糊
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 14)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .animation(shown ? .smooth(duration: 1.1).delay(delay) : .easeIn(duration: 0.35), value: shown)
    }
}

extension View {
    /// 从模糊、下沉、透明 过渡到 清晰、归位、不透明
    func reveal(_ shown: Bool, delay: Double) -> some View {
        modifier(Reveal(shown: shown, delay: delay))
    }
}

private struct Shake: GeometryEffect {
    var attempts: CGFloat
    var animatableData: CGFloat {
        get { attempts }
        set { attempts = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(attempts * .pi * 6), y: 0))
    }
}
