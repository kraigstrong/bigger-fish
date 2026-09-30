import AVFoundation
import UIKit

// Math Reef sound effects and music (sources and licenses in Sounds/CREDITS.md).
// Sound plays even when the phone is on silent: a kid handed a parent's phone won't know to flip the
// switch, and the game feels dead without it. The volume buttons still work, and other apps' audio
// (a podcast, music) keeps playing underneath.

enum ReefSound: String, CaseIterable {
    case gulp, wrong, mapJingle = "map-jingle", star, crown

    /// Stars ring up to three times in quick succession, so their rings overlap.
    fileprivate var voices: Int { self == .star ? 3 : 1 }
}

enum ReefMusic: String, CaseIterable {
    /// Under the reef map, a world's level path, and a level's instructions.
    case menu = "menu-music"
    /// While the fish swims.
    case game = "game-music"
}

/// The parts of `AVAudioPlayer` that `ReefAudio` uses, so tests can swap in stand-ins that don't
/// need an audio device.
protocol AudioVoice: AnyObject {
    var isPlaying: Bool { get }
    var volume: Float { get set }
    var currentTime: TimeInterval { get set }
    var numberOfLoops: Int { get set }
    @discardableResult func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    func pause()
    func stop()
    func setVolume(_ volume: Float, fadeDuration: TimeInterval)
}

extension AVAudioPlayer: AudioVoice {}

final class ReefAudio {
    /// Music sits under the effects; both tracks are normalized to -18 LUFS before this.
    static let musicVolume: Float = 0.45

    private let defaults: UserDefaults
    private var players: [ReefSound: [AudioVoice]] = [:]
    private var musicPlayers: [ReefMusic: AudioVoice] = [:]
    /// The track the current screen wants, even while sound is off.
    private(set) var currentMusic: ReefMusic?
    /// Bumped on every music change so a stale delayed start or fade-out pause does nothing.
    private var musicGeneration = 0
    private static let soundOnKey = "mathReef.soundOn"

    /// Parents can turn all sound off in Settings; remembered across launches. Turning it back on
    /// resumes whatever music the current screen wants.
    var isSoundOn: Bool {
        didSet {
            guard isSoundOn != oldValue else { return }
            defaults.set(isSoundOn, forKey: Self.soundOnKey)
            musicGeneration += 1
            if isSoundOn {
                guard let player = currentMusic.flatMap({ musicPlayers[$0] }) else { return }
                player.play()
                player.setVolume(Self.musicVolume, fadeDuration: 0.5)
            } else {
                players.values.joined().forEach { $0.stop() }
                musicPlayers.values.forEach { $0.pause(); $0.volume = 0 }
            }
        }
    }

    /// - Parameters:
    ///   - defaults: where the sound setting is remembered.
    ///   - makeVoice: loads a sound file by name and extension; tests pass stand-ins.
    init(defaults: UserDefaults = .standard, makeVoice: (String, String) -> AudioVoice? = ReefAudio.bundleVoice) {
        self.defaults = defaults
        isSoundOn = defaults.object(forKey: Self.soundOnKey) as? Bool ?? true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
        for sound in ReefSound.allCases {
            players[sound] = (0..<sound.voices).compactMap { _ in
                let player = makeVoice(sound.rawValue, "caf")
                player?.prepareToPlay()
                return player
            }
        }
        for music in ReefMusic.allCases {
            guard let player = makeVoice(music.rawValue, "m4a") else { continue }
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            musicPlayers[music] = player
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pauseForBackground), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeFromBackground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    static func bundleVoice(named name: String, extension ext: String) -> AudioVoice? {
        Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? AVAudioPlayer(contentsOf: $0) }
    }

    /// Plays on a free voice, or restarts the first one if they're all busy.
    func play(_ sound: ReefSound) {
        guard isSoundOn, let voices = players[sound], let first = voices.first else { return }
        let player = voices.first { !$0.isPlaying } ?? first
        player.currentTime = 0
        player.play()
        logForCapture("sound \(sound.rawValue)")
    }

    /// Fades to `music` (or to silence with nil). Asking for the track that's already playing does
    /// nothing, so moving between menus doesn't restart it. Each track resumes where it left off.
    /// With sound off, this only records which track the screen wants.
    func playMusic(_ music: ReefMusic?, after delay: TimeInterval = 0, fade: TimeInterval = 1.0) {
        guard music != currentMusic else { return }
        logForCapture("music \(music?.rawValue ?? "none") \(delay) \(fade)")
        musicGeneration += 1
        let generation = musicGeneration
        if let old = currentMusic.flatMap({ musicPlayers[$0] }) {
            old.setVolume(0, fadeDuration: fade)
            DispatchQueue.main.asyncAfter(deadline: .now() + fade) { [weak self] in
                // Only pause if nothing has asked for this track again in the meantime.
                guard let self, self.currentMusic.flatMap({ self.musicPlayers[$0] }) !== old else { return }
                old.pause()
            }
        }
        currentMusic = music
        guard let music, let player = musicPlayers[music] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.musicGeneration == generation, self.isSoundOn else { return }
            player.play()
            player.setVolume(Self.musicVolume, fadeDuration: fade)
        }
    }

    /// The simulator can't record sound, so a store capture logs each cue with its time and
    /// `scripts/store-capture.sh` rebuilds the soundtrack from the same files.
    private func logForCapture(_ cue: String) {
        #if DEBUG
        guard StoreCapture.scene != nil else { return }
        print("STORE-CAPTURE-AUDIO \(Date().timeIntervalSince1970) \(cue)")
        #endif
    }

    @objc func pauseForBackground() {
        currentMusic.flatMap { musicPlayers[$0] }?.pause()
    }

    @objc func resumeFromBackground() {
        guard isSoundOn, let player = currentMusic.flatMap({ musicPlayers[$0] }), player.volume > 0 else { return }
        player.play()
    }
}
