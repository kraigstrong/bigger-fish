import AVFoundation
import Combine
import UIKit

/// The player's sound choices, saved on the device.
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

/// Bigger Fish's sound effects and music (sources and licenses in Sounds/CREDITS.md).
/// Consolidation with Math Reef's audio can follow its release.
final class ArcadeAudio {
    static let shared = ArcadeAudio()
    /// Raw values are the `.caf` files in Sounds/.
    enum Effect: String, CaseIterable {
        case eat = "pop", bounce = "gulp", sting = "zap", lose = "wrong", clear = "win"
    }
    /// Raw values are the `.m4a` files in Sounds/.
    enum Music: String, CaseIterable {
        /// Under the world map and level maps.
        case menu = "menu-music"
        /// Under a level, from its ready screen to its result.
        case game = "game-music"
    }

    // Audio-session activation and AVAudioPlayer.play can block. Keep every player and the music
    // state on one worker so a gulp cannot hold up the SpriteKit frame loop.
    private let queue = DispatchQueue(label: "biggerFish.audio", qos: .userInitiated)
    private var voices: [Effect: [AVAudioPlayer]] = [:]
    private var musicPlayers: [Music: AVAudioPlayer] = [:]
    /// The track the current screen wants, even while music is off.
    private var currentMusic: Music?
    private var musicOn: Bool
    private let settings: ArcadeSettings
    private var musicSwitch: AnyCancellable?

    init(settings: ArcadeSettings = .shared) {
        self.settings = settings
        musicOn = settings.musicOn
        queue.async { [self] in prepare() }
        musicSwitch = settings.$musicOn.dropFirst().removeDuplicates().sink { [weak self] on in
            self?.queue.async { self?.setMusicOn(on) }
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pauseForBackground),
                           name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeFromBackground),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func prepare() {
        // Playback (not ambient) plays with the ringer switch on silent; the in-game switches decide.
        // Mixing keeps the player's own music or podcast going underneath.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
        for effect in Effect.allCases {
            voices[effect] = (0..<3).compactMap { _ in
                guard let player = Self.player(effect.rawValue, "caf") else { return nil }
                if effect == .bounce { player.enableRate = true; player.rate = GameTuning.bounceSoundRate }
                player.volume = effect == .clear ? GameTuning.clearSoundVolume : GameTuning.effectVolume
                player.prepareToPlay()
                return player
            }
        }
        for music in Music.allCases {
            guard let player = Self.player(music.rawValue, "m4a") else { continue }
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            musicPlayers[music] = player
        }
    }

    private static func player(_ name: String, _ ext: String) -> AVAudioPlayer? {
        Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? AVAudioPlayer(contentsOf: $0) }
    }

    func play(_ effect: Effect) {
        guard settings.soundEffectsOn else { return }
        queue.async { [self] in
            guard let pool = voices[effect], let voice = pool.first(where: { !$0.isPlaying }) ?? pool.first else { return }
            voice.currentTime = 0
            voice.play()
        }
    }

    /// Fades to `music`, or to silence with nil. Asking for the track that's already playing does
    /// nothing, so moving between maps doesn't restart it; each track resumes where it left off.
    func playMusic(_ music: Music?) {
        queue.async { [self] in
            guard music != currentMusic else { return }
            let fade = GameTuning.musicFadeSeconds
            if let old = currentMusic.flatMap({ musicPlayers[$0] }) {
                old.setVolume(0, fadeDuration: fade)
                queue.asyncAfter(deadline: .now() + fade) { [self] in
                    // Only pause if nothing has asked for this track again in the meantime.
                    guard currentMusic.flatMap({ musicPlayers[$0] }) !== old else { return }
                    old.pause()
                }
            }
            currentMusic = music
            guard musicOn, let player = music.flatMap({ musicPlayers[$0] }) else { return }
            player.play()
            player.setVolume(GameTuning.musicVolume, fadeDuration: fade)
        }
    }

    private func setMusicOn(_ on: Bool) {
        musicOn = on
        if on, let player = currentMusic.flatMap({ musicPlayers[$0] }) {
            player.play()
            player.setVolume(GameTuning.musicVolume, fadeDuration: 0.5)
        } else if !on {
            musicPlayers.values.forEach { $0.pause(); $0.volume = 0 }
        }
    }

    @objc private func pauseForBackground() {
        // Both tracks, in case this lands mid-crossfade; only the current one resumes.
        queue.async { [self] in musicPlayers.values.forEach { $0.pause() } }
    }

    @objc private func resumeFromBackground() {
        queue.async { [self] in
            guard musicOn, let player = currentMusic.flatMap({ musicPlayers[$0] }), player.volume > 0 else { return }
            player.play()
        }
    }
}
