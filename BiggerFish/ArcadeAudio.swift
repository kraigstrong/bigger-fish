import AVFoundation
import Combine

/// The player's sound choices, saved on the device. Music has no tracks yet (#78); its switch is ready for them.
final class ArcadeSettings: ObservableObject {
    static let shared = ArcadeSettings()
    private static let effectsKey = "biggerFish.soundEffectsOn"
    private static let musicKey = "biggerFish.musicOn"
    private let defaults: UserDefaults

    @Published var soundEffectsOn: Bool { didSet { defaults.set(soundEffectsOn, forKey: Self.effectsKey) } }
    @Published var musicOn: Bool { didSet { defaults.set(musicOn, forKey: Self.musicKey) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundEffectsOn = defaults.object(forKey: Self.effectsKey) as? Bool ?? true
        musicOn = defaults.object(forKey: Self.musicKey) as? Bool ?? true
    }
}

/// Small local effect pool; consolidation with Math Reef's audio can follow its release.
final class ArcadeAudio {
    static let shared = ArcadeAudio()
    enum Effect: String, CaseIterable { case eat = "gulp", bounce = "bounce", lose = "wrong", clear = "star" }
    // Audio-session activation and AVAudioPlayer.play can block. Keep the entire
    // voice pool on one worker so a gulp cannot hold up the SpriteKit frame loop.
    private let queue = DispatchQueue(label: "biggerFish.audio", qos: .userInitiated)
    private var voices: [Effect: [AVAudioPlayer]] = [:]
    private let settings: ArcadeSettings

    init(settings: ArcadeSettings = .shared) {
        self.settings = settings
        queue.async { [self] in prepareVoices() }
    }

    private func prepareVoices() {
        // Playback (not ambient) plays with the ringer switch on silent; the in-game switches decide.
        // Mixing keeps the player's own music or podcast going underneath.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
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
        guard settings.soundEffectsOn else { return }
        queue.async { [self] in
            guard let pool = voices[effect], let voice = pool.first(where: { !$0.isPlaying }) ?? pool.first else { return }
            voice.currentTime = 0
            voice.play()
        }
    }
}
