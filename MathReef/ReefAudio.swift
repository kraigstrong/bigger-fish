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

final class ReefAudio {
    /// Music sits under the effects; both tracks are normalized to -18 LUFS before this.
    static let musicVolume: Float = 0.45

    private var players: [ReefSound: [AVAudioPlayer]] = [:]
    private var musicPlayers: [ReefMusic: AVAudioPlayer] = [:]
    private var currentMusic: ReefMusic?
    /// Bumped on every music change so a stale delayed start or fade-out pause does nothing.
    private var musicGeneration = 0
    private static let soundOnKey = "mathReef.soundOn"

    /// Parents can turn all sound off in Settings; remembered across launches. Turning it back on
    /// resumes whatever music the current screen wants.
    var isSoundOn: Bool {
        didSet {
            guard isSoundOn != oldValue else { return }
            UserDefaults.standard.set(isSoundOn, forKey: Self.soundOnKey)
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

    init() {
        isSoundOn = UserDefaults.standard.object(forKey: Self.soundOnKey) as? Bool ?? true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
        for sound in ReefSound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else { continue }
            players[sound] = (0..<sound.voices).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
                return player
            }
        }
        for music in ReefMusic.allCases {
            guard let url = Bundle.main.url(forResource: music.rawValue, withExtension: "m4a"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            musicPlayers[music] = player
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pauseForBackground), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeFromBackground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    /// Plays on a free voice, or restarts the first one if they're all busy.
    func play(_ sound: ReefSound) {
        guard isSoundOn, let voices = players[sound], let first = voices.first else { return }
        let player = voices.first { !$0.isPlaying } ?? first
        player.currentTime = 0
        player.play()
    }

    /// Fades to `music` (or to silence with nil). Asking for the track that's already playing does
    /// nothing, so moving between menus doesn't restart it. Each track resumes where it left off.
    /// With sound off, this only records which track the screen wants.
    func playMusic(_ music: ReefMusic?, after delay: TimeInterval = 0, fade: TimeInterval = 1.0) {
        guard music != currentMusic else { return }
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

    @objc private func pauseForBackground() {
        currentMusic.flatMap { musicPlayers[$0] }?.pause()
    }

    @objc private func resumeFromBackground() {
        guard isSoundOn, let player = currentMusic.flatMap({ musicPlayers[$0] }), player.volume > 0 else { return }
        player.play()
    }
}
