import AVFoundation

/// 播放打包在 App 里的音效（Resources/Sounds/*.wav）。同一个音效可以叠着播放。
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Sound: String {
        case enter, unlock, wrong, hold
    }

    private var pool: [String: [AVAudioPlayer]] = [:]
    private let volume: Float = 0.8

    private init() {
        // 预加载，第一次播放不卡顿
        for name in ["enter", "unlock", "wrong", "hold"] + (0..<10).map({ "note\($0)" }) {
            _ = player(for: name)
        }
    }

    func play(_ sound: Sound) { play(name: sound.rawValue) }

    /// 打对第 index 个字（从 0 开始）时的音符
    func playNote(_ index: Int, delay: TimeInterval = 0) {
        let name = "note\(min(max(index, 0), 9))"
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.play(name: name) }
        } else {
            play(name: name)
        }
    }

    func stop(_ sound: Sound, fade: TimeInterval) {
        for player in pool[sound.rawValue] ?? [] where player.isPlaying {
            player.setVolume(0, fadeDuration: fade)
            DispatchQueue.main.asyncAfter(deadline: .now() + fade) { player.stop() }
        }
    }

    private func play(name: String) {
        guard FocusStore.shared.soundEnabled, let player = player(for: name) else { return }
        player.currentTime = 0
        player.volume = volume
        player.play()
    }

    private func player(for name: String) -> AVAudioPlayer? {
        if let idle = pool[name]?.first(where: { !$0.isPlaying }) { return idle }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        pool[name, default: []].append(player)
        return player
    }
}
