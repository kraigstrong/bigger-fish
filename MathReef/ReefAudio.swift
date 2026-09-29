import AVFoundation

// Math Reef sound effects, all from Mixkit's free sound effects library (see Sounds/CREDITS.md).
// The ambient session respects the ring/silent switch and mixes with whatever else is playing.

enum ReefSound: String, CaseIterable {
    case gulp, wrong, mapJingle = "map-jingle", star, crown

    /// Stars ring up to three times in quick succession, so their rings overlap.
    fileprivate var voices: Int { self == .star ? 3 : 1 }
}

final class ReefAudio {
    private var players: [ReefSound: [AVAudioPlayer]] = [:]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for sound in ReefSound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else { continue }
            players[sound] = (0..<sound.voices).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                return player
            }
        }
    }

    /// Plays on a free voice, or restarts the first one if they're all busy.
    func play(_ sound: ReefSound) {
        guard let voices = players[sound], let first = voices.first else { return }
        let player = voices.first { !$0.isPlaying } ?? first
        player.currentTime = 0
        player.play()
    }
}
