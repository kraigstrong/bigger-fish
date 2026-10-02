import AVFoundation

/// Small local effect pool; consolidation with Math Reef's audio can follow its release.
final class ArcadeAudio {
    enum Effect: String, CaseIterable { case eat = "gulp", bounce = "bounce", lose = "wrong", clear = "star" }
    // Audio-session activation and AVAudioPlayer.play can block. Keep the entire
    // voice pool on one worker so a gulp cannot hold up the SpriteKit frame loop.
    private let queue = DispatchQueue(label: "biggerFish.audio", qos: .userInitiated)
    private var voices: [Effect: [AVAudioPlayer]] = [:]

    init() {
        queue.async { [self] in prepareVoices() }
    }

    private func prepareVoices() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        for effect in Effect.allCases {
            let name = effect == .bounce ? "gulp" : effect.rawValue
            voices[effect] = (0..<3).compactMap { _ in
                guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
                      let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
                if effect == .bounce { player.enableRate = true; player.rate = 1.35 }
                player.volume = effect == .clear ? 0.55 : 0.7
                player.prepareToPlay()
                return player
            }
        }
    }

    func play(_ effect: Effect) {
        queue.async { [self] in
            guard let pool = voices[effect], let voice = pool.first(where: { !$0.isPlaying }) ?? pool.first else { return }
            voice.currentTime = 0
            voice.play()
        }
    }
}
