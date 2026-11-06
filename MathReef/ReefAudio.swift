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

/// Called from the main thread, as the scene does. The settings and the track the screen wants live there; the
/// players live on `queue`, as Bigger Fish's do (ArcadeAudio.swift).
final class ReefAudio {
    /// Music sits under the effects; both tracks are normalized to -18 LUFS before this.
    static let musicVolume: Float = 0.45

    private let defaults: UserDefaults
    /// The track the current screen wants, even while music is off.
    private(set) var currentMusic: ReefMusic?
    private static let soundOnKey = "mathReef.soundOn"
    private static let musicOnKey = "mathReef.musicOn"

    // Audio-session activation and AVAudioPlayer.play can block. Keep every player and the music
    // state below on one worker so a gulp cannot hold up the SpriteKit frame loop.
    private let queue = DispatchQueue(label: "mathReef.audio", qos: .userInitiated)
    private var players: [ReefSound: [AudioVoice]] = [:]
    private var musicPlayers: [ReefMusic: AudioVoice] = [:]
    /// The queue's own `currentMusic` and `isMusicOn`. Changes reach it in the order the scene made them.
    private var track: ReefMusic?
    private var musicOn: Bool
    /// Bumped on every music change so a stale delayed start does nothing.
    private var musicGeneration = 0

    /// The sound effects. Parents can turn them off in Settings; remembered across launches.
    var isSoundOn: Bool {
        didSet {
            guard isSoundOn != oldValue else { return }
            defaults.set(isSoundOn, forKey: Self.soundOnKey)
            if !isSoundOn { queue.async { [self] in players.values.joined().forEach { $0.stop() } } }
        }
    }

    /// The music, with its own switch in Settings; remembered across launches. Turning it back on
    /// resumes whatever music the current screen wants.
    var isMusicOn: Bool {
        didSet {
            guard isMusicOn != oldValue else { return }
            defaults.set(isMusicOn, forKey: Self.musicOnKey)
            let on = isMusicOn
            queue.async { [self] in setMusicOn(on) }
        }
    }

    #if DEBUG
    /// Each audio cue and when it was asked for on the game's clock (`logForCapture`). A store capture prints them;
    /// tests listen in.
    var captureCues: ((TimeInterval, String) -> Void)? =
        StoreCapture.scene == nil ? nil : { print("STORE-CAPTURE-AUDIO \($0) \($1)") }
    #endif

    /// - Parameters:
    ///   - defaults: where the sound and music settings are remembered.
    ///   - makeVoice: loads a sound file by name and extension, on the audio queue; tests pass stand-ins.
    init(defaults: UserDefaults = .standard,
         makeVoice: @escaping (String, String) -> AudioVoice? = ReefAudio.bundleVoice) {
        self.defaults = defaults
        isSoundOn = defaults.object(forKey: Self.soundOnKey) as? Bool ?? true
        // Before 1.1 the sound switch silenced the music too, so an install that turned it off keeps
        // the music off. Saved now, so the music no longer follows that switch.
        if defaults.object(forKey: Self.musicOnKey) == nil { defaults.set(isSoundOn, forKey: Self.musicOnKey) }
        isMusicOn = defaults.bool(forKey: Self.musicOnKey)
        musicOn = isMusicOn
        queue.async { [self] in prepare(makeVoice) }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pauseForBackground), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeFromBackground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func prepare(_ makeVoice: (String, String) -> AudioVoice?) {
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
    }

    static func bundleVoice(named name: String, extension ext: String) -> AudioVoice? {
        Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? AVAudioPlayer(contentsOf: $0) }
    }

    /// Plays on a free voice, or restarts the first one if they're all busy.
    func play(_ sound: ReefSound) {
        guard isSoundOn else { return }
        logForCapture("sound \(sound.rawValue)")
        queue.async { [self] in
            guard let voices = players[sound], let first = voices.first else { return }
            let player = voices.first { !$0.isPlaying } ?? first
            player.currentTime = 0
            player.play()
        }
    }

    /// Fades to `music` (or to silence with nil). Asking for the track that's already playing does
    /// nothing, so moving between menus doesn't restart it. Each track resumes where it left off.
    /// With music off, this only records which track the screen wants.
    func playMusic(_ music: ReefMusic?, after delay: TimeInterval = 0, fade: TimeInterval = 1.0) {
        guard music != currentMusic else { return }
        logForCapture("music \(music?.rawValue ?? "none") \(delay) \(fade)")
        currentMusic = music
        // The delay counts from now, not from when the queue gets to it.
        let start = DispatchTime.now() + delay
        queue.async { [self] in switchMusic(to: music, at: start, fade: fade) }
    }

    private func switchMusic(to music: ReefMusic?, at start: DispatchTime, fade: TimeInterval) {
        musicGeneration += 1
        let generation = musicGeneration
        if let old = track.flatMap({ musicPlayers[$0] }) {
            old.setVolume(0, fadeDuration: fade)
            queue.asyncAfter(deadline: .now() + fade) { [weak self] in
                // Only pause if nothing has asked for this track again in the meantime.
                guard let self, self.track.flatMap({ self.musicPlayers[$0] }) !== old else { return }
                old.pause()
            }
        }
        track = music
        guard let music, let player = musicPlayers[music] else { return }
        queue.asyncAfter(deadline: start) { [weak self] in
            guard let self, self.musicGeneration == generation, self.musicOn else { return }
            player.play()
            player.setVolume(Self.musicVolume, fadeDuration: fade)
        }
    }

    private func setMusicOn(_ on: Bool) {
        musicOn = on
        musicGeneration += 1
        if on {
            guard let player = track.flatMap({ musicPlayers[$0] }) else { return }
            player.play()
            player.setVolume(Self.musicVolume, fadeDuration: 0.5)
        } else {
            musicPlayers.values.forEach { $0.pause(); $0.volume = 0 }
        }
    }

    /// The simulator can't record sound, so a store capture logs each cue with its time and
    /// `scripts/store-capture.sh` rebuilds the soundtrack from the same files. The time is taken here, on the
    /// main thread with the game's clock, so a cue the queue gets to late still lines up with the video.
    private func logForCapture(_ cue: String) {
        #if DEBUG
        captureCues?(StoreCapture.now(), cue)
        #endif
    }

    @objc func pauseForBackground() {
        // Both tracks, in case this lands mid-crossfade; only the current one resumes.
        queue.async { [self] in musicPlayers.values.forEach { $0.pause() } }
    }

    @objc func resumeFromBackground() {
        queue.async { [self] in
            guard musicOn, let player = track.flatMap({ musicPlayers[$0] }), player.volume > 0 else { return }
            player.play()
        }
    }

    #if DEBUG
    /// For tests: waits until the queue has done the work asked of it so far. Delayed starts and fade-outs come later.
    func waitForQueue() {
        queue.sync {}
    }
    #endif
}
