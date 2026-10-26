import AppKit
import SwiftUI

@Observable
final class ShieldModel {
    var appeared = false
    var appName = ""
    var appIcon = NSImage()
    var occurrence: Occurrence?
    var quote = Quotes.random()
    var passesLeft = 0
    var holding = false
    var holdProgress: Double = 0

    var onBack: () -> Void = {}
    var onHoldChanged: (Bool) -> Void = { _ in }
    var onHoldCompleted: () -> Void = {}
}

/// 打开被限制的 App 时盖上来的界面。
/// 中间是褪了色的 App 图标，外面一圈像灯油一样慢慢燃尽的环：时段还剩多少，就亮多少。
struct ShieldView: View {
    @Bindable var model: ShieldModel
    let showsContent: Bool

    var body: some View {
        ZStack {
            Atmosphere()
                .opacity(model.appeared ? 1 : 0)
                .animation(.easeInOut(duration: model.appeared ? 1.0 : 0.4), value: model.appeared)

            if showsContent, let occurrence = model.occurrence {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(occurrence, now: context.date)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ occurrence: Occurrence, now: Date) -> some View {
        let rule = occurrence.rule
        return VStack(spacing: 0) {
            Spacer(minLength: 60)

            HStack(spacing: 8) {
                Circle().fill(RuleTint.color(rule.tint)).frame(width: 7, height: 7)
                Text("\(rule.name) · 进行中")
            }
            .font(.system(size: 12, weight: .semibold))
            .tracking(3)
            .opacity(0.7)
            .reveal(model.appeared, delay: 0.35)
            .padding(.bottom, 36)

            LampRing(icon: model.appIcon, remaining: 1 - occurrence.progress(at: now),
                     tint: rule.tint, lit: model.appeared)
                .frame(width: 176, height: 176)
                .reveal(model.appeared, delay: 0.1)
                .padding(.bottom, 44)

            Text("此刻，先不打开 \(model.appName)")
                .font(.custom("STSongti-SC-Bold", size: 42))
                .tracking(2)
                .multilineTextAlignment(.center)
                .reveal(model.appeared, delay: 0.5)

            Text("「\(rule.name)」\(ScheduleText.moment(occurrence.end, from: now)) 结束 · 还有 \(ScheduleText.remaining(until: occurrence.end, from: now))")
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .opacity(0.62)
                .padding(.top, 18)
                .reveal(model.appeared, delay: 0.65)

            Spacer(minLength: 40)

            Text(model.quote.text)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
                .opacity(0.42)
                .reveal(model.appeared, delay: 0.85)
                .padding(.bottom, 34)

            ShieldActions(model: model, rule: rule)
                .reveal(model.appeared, delay: 1.0)
                .padding(.bottom, 60)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 2)
        .accessibilityElement(children: .contain)
    }
}

/// 图标 + 燃尽环。环的头上有一点灯火，跟着剩余时间往回走
private struct LampRing: View {
    let icon: NSImage
    let remaining: Double
    let tint: Int
    let lit: Bool

    var body: some View {
        let shown = lit ? remaining : 0
        let color = RuleTint.color(tint)
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(AngularGradient(colors: [color.opacity(0.25), color], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(shown, 0.01))),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.8), radius: 8)

                // 环头的灯火
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                    .shadow(color: color, radius: 6)
                    .shadow(color: color.opacity(0.8), radius: 14)
                    .offset(x: radius * sin(2 * .pi * shown), y: -radius * cos(2 * .pi * shown))
                    .opacity(shown > 0.005 ? 1 : 0)

                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.56, height: size * 0.56)
                    .saturation(0.12)
                    .opacity(0.88)
                    .scaleEffect(lit ? 1 : 1.12)
                    .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
            }
            .frame(width: size, height: size)
            .animation(.smooth(duration: 1.4).delay(lit ? 0.2 : 0), value: lit)
        }
        .accessibilityElement()
        .accessibilityLabel("时段还剩 \(Int(remaining * 100))%")
    }
}

private struct ShieldActions: View {
    @Bindable var model: ShieldModel
    let rule: BlockRule

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                if model.passesLeft > 0 {
                    HoldToPass(model: model)
                }
                Button(action: model.onBack) {
                    Label("回到学习", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Brand.gradient, in: .capsule)
                        .overlay { Capsule().strokeBorder(.white.opacity(0.2)) }
                        .shadow(color: Brand.glow.opacity(0.4), radius: 14, y: 4)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .keyboardShortcut(.defaultAction)

                // Esc 也是回到学习
                Button("", action: model.onBack)
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }

            Text(footnote)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.42)
        }
    }

    private var footnote: String {
        if rule.isStrict { return "严格时段 · 结束前不能跳过，回到学习时会退出 \(model.appName)" }
        if model.passesLeft == 0 { return "今天的临时使用次数已经用完了" }
        return "按回车回到学习"
    }
}

/// 按住 3 秒，临时再用 5 分钟：胶囊从左往右被填满，中途松手会弹回去
private struct HoldToPass: View {
    @Bindable var model: ShieldModel

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: model.holdProgress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15, height: 15)
            Text(model.holding ? "继续按住…" : "按住，再用 \(ScheduleStore.passMinutes) 分钟")
                .contentTransition(.interpolate)
            Text("剩 \(model.passesLeft) 次")
                .opacity(0.5)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(width: proxy.size.width * model.holdProgress)
            }
        }
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(Capsule())
        .animation(.smooth(duration: 0.3), value: model.holding)
        .onLongPressGesture(minimumDuration: ShieldController.holdSeconds, maximumDistance: 60,
                            perform: model.onHoldCompleted, onPressingChanged: model.onHoldChanged)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("按住三秒，临时使用 \(ScheduleStore.passMinutes) 分钟")
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
