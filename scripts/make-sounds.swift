// 离线合成 Focus 的音效（不依赖任何素材），输出 44.1kHz 16-bit 立体声 WAV。
// 用法：swift scripts/make-sounds.swift <输出目录>
import Foundation

let sampleRate = 44_100.0
let outputDir = CommandLine.arguments.dropFirst().first ?? "Sounds"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// MARK: - 基础工具

struct Rng { // 固定种子，保证每次生成一样
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 1_000_000) / 500_000 - 1
    }
}
var rng = Rng()

func buffer(_ seconds: Double) -> [Double] { Array(repeating: 0, count: Int(seconds * sampleRate)) }

/// 加一个音：sin 分音叠加，每个分音有自己的衰减
func addTone(_ out: inout [Double], at start: Double, freq: Double, amp: Double,
             partials: [(ratio: Double, amp: Double, decay: Double)], attack: Double = 0.003) {
    let first = Int(start * sampleRate)
    for i in first..<out.count {
        let t = Double(i - first) / sampleRate
        let env = min(1, t / attack)
        var v = 0.0
        for p in partials {
            v += p.amp * exp(-t / p.decay) * sin(2 * .pi * freq * p.ratio * t)
        }
        out[i] += amp * env * v
    }
}

/// 简单的 Schroeder 混响，左右声道用略不同的延时，得到空间感
func reverb(_ dry: [Double], wet: Double, room: Double = 0.84, damp: Double = 0.3) -> (l: [Double], r: [Double]) {
    func channel(_ spread: Int) -> [Double] {
        let combs = [1116, 1188, 1277, 1356, 1422, 1491].map { $0 + spread }
        var out = Array(repeating: 0.0, count: dry.count)
        for delay in combs {
            var line = Array(repeating: 0.0, count: delay)
            var idx = 0, store = 0.0
            for i in 0..<dry.count {
                let y = line[idx]
                store = y * (1 - damp) + store * damp
                line[idx] = dry[i] * 0.015 + store * room
                idx = (idx + 1) % delay
                out[i] += y
            }
        }
        for delay in [556, 441, 341].map({ $0 + spread }) {
            var line = Array(repeating: 0.0, count: delay)
            var idx = 0
            for i in 0..<out.count {
                let buf = line[idx]
                let y = -out[i] + buf
                line[idx] = out[i] + buf * 0.5
                idx = (idx + 1) % delay
                out[i] = y
            }
        }
        return zip(dry, out).map { $0 * (1 - wet) + $1 * wet * 3 }
    }
    return (channel(0), channel(23))
}

func write(_ name: String, _ stereo: (l: [Double], r: [Double]), gain: Double = 1) {
    // 结尾 30ms 淡出，避免爆音
    let n = stereo.l.count, fade = Int(0.03 * sampleRate)
    var data = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 4))
    data.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(2)
    u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 4); u16(4); u16(16)
    data.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 4))
    for i in 0..<n {
        let tail = i > n - fade ? Double(n - i) / Double(fade) : 1
        for s in [stereo.l[i], stereo.r[i]] {
            let v = max(-1, min(1, s * gain * tail))
            u16(UInt16(bitPattern: Int16(v * 32_000)))
        }
    }
    try! data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).wav"))
    print("  \(name).wav")
}

func lowpass(_ x: inout [Double], cutoff: (Double) -> Double) {
    var y = 0.0
    for i in 0..<x.count {
        let t = Double(i) / sampleRate
        let a = 1 - exp(-2 * .pi * cutoff(t) / sampleRate)
        y += a * (x[i] - y)
        x[i] = y
    }
}

func smoothstep(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }

// MARK: - 开始专注：温暖的和弦慢慢浮起 + 一缕气流

do {
    var out = buffer(4.0)
    let chord = [146.83, 220.00, 329.63, 369.99, 554.37] // D3 A3 E4 F#4 C#5（Dmaj9）
    for (k, f) in chord.enumerated() {
        for detune in [0.9985, 1.0015] {
            let phase = Double(k) * 0.7
            for i in 0..<out.count {
                let t = Double(i) / sampleRate
                let env = smoothstep(t / 0.9) * (t < 1.4 ? 1 : exp(-(t - 1.4) / 0.55))
                out[i] += 0.022 * env * sin(2 * .pi * f * detune * t + phase)
            }
        }
    }
    // 沙沙声：比和弦更早起、更晚落，带一点树叶般不规则的起伏
    var air = (0..<out.count).map { _ in rng.next() }
    lowpass(&air) { t in 350 + 2300 * exp(-pow((t - 1.0) / 0.8, 2)) }
    for i in 0..<out.count {
        let t = Double(i) / sampleRate
        let flutter = 1 + 0.25 * sin(2 * .pi * 5.3 * t) * sin(2 * .pi * 0.9 * t)
        out[i] += 0.11 * air[i] * flutter * exp(-pow((t - 1.0) / 0.85, 2))
    }
    write("enter", reverb(out, wet: 0.35), gain: 1.4)
}

// MARK: - 打对一个字：五声音阶上的拇指琴音，整句打完是一段上行旋律

// 像隔着毛毡轻敲的木琴：音区更低、起音更缓、没有拨片声和亮的泛音，尾巴柔和地散在混响里
let pentatonic = [440.00, 493.88, 587.33, 659.25, 739.99, 880.00, 987.77, 1174.66, 1318.51, 1479.98]
for (index, freq) in pentatonic.enumerated() {
    var out = buffer(1.4)
    addTone(&out, at: 0, freq: freq, amp: 0.10, partials: [
        (1, 1, 0.42), (2.0, 0.06, 0.15),
    ], attack: 0.012)
    lowpass(&out) { _ in 2400 }
    write("note\(index)", reverb(out, wet: 0.4))
}

// MARK: - 解锁成功：钟声琶音

do {
    var out = buffer(3.6)
    let bell: [(ratio: Double, amp: Double, decay: Double)] = [(1, 1, 1.6), (2.0, 0.32, 0.8), (2.76, 0.16, 0.45), (5.4, 0.06, 0.15)]
    for (k, f) in [587.33, 880.00, 1174.66, 1479.98].enumerated() { // D5 A5 D6 F#6
        addTone(&out, at: Double(k) * 0.085, freq: f, amp: 0.12, partials: bell, attack: 0.002)
    }
    write("unlock", reverb(out, wet: 0.38))
}

// MARK: - 输错：两个低沉柔和的音

do {
    var out = buffer(0.7)
    for (k, f) in [233.08, 196.00].enumerated() { // Bb3 → G3
        addTone(&out, at: Double(k) * 0.11, freq: f, amp: 0.26, partials: [(1, 1, 0.12), (2, 0.15, 0.05)], attack: 0.004)
    }
    lowpass(&out) { _ in 1400 }
    write("wrong", reverb(out, wet: 0.2))
}

// MARK: - 长按：像一次缓慢的吸气，越来越亮（和长按时长一致：4 秒）

do {
    let hold = 4.0
    var out = buffer(hold + 0.4)
    var air = (0..<out.count).map { _ in rng.next() }
    lowpass(&air) { t in 250 + 2600 * pow(min(t / hold, 1), 1.6) }
    for i in 0..<out.count {
        let t = Double(i) / sampleRate
        let p = min(t / hold, 1)
        let env = pow(p, 1.4) * (t > hold ? exp(-(t - hold) / 0.08) : 1)
        let glide = 220 * pow(2, p) // A3 → A4
        out[i] = 0.16 * env * air[i] + 0.035 * env * sin(2 * .pi * glide * t)
    }
    write("hold", reverb(out, wet: 0.3))
}

print("音效已生成到 \(outputDir)")
