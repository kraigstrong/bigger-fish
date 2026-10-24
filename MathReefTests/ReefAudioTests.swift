import Foundation
import Testing
@testable import MathReef

/// Stands in for `AVAudioPlayer`, so these tests don't need an audio device (CI machines may not
/// have one).
private final class FakeVoice: AudioVoice {
    var isPlaying = false
    var volume: Float = 1
    var currentTime: TimeInterval = 0
    var numberOfLoops = 0
    var playCount = 0

    func prepareToPlay() -> Bool { true }
    func play() -> Bool {
        isPlaying = true
        playCount += 1
        return true
    }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
    func setVolume(_ volume: Float, fadeDuration: TimeInterval) { self.volume = volume }
}

/// The sound and music switches and the music handoffs between screens. Music starts and fades on the main queue,
/// so tests pass no fade and give the queue a moment (`settle`) before checking.
@MainActor
struct ReefAudioTests {
    private let defaults: UserDefaults

    init() {
        let name = "ReefAudioTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    private func makeAudio() -> (ReefAudio, (String) -> [FakeVoice]) {
        final class Box { var voices: [String: [FakeVoice]] = [:] }
        let box = Box()
        let audio = ReefAudio(defaults: defaults) { name, _ in
            let voice = FakeVoice()
            box.voices[name, default: []].append(voice)
            return voice
        }
        return (audio, { box.voices[$0] ?? [] })
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(200))  // generous for slow CI machines
    }

    @Test func soundIsOnByDefaultAndTheSettingIsRemembered() {
        let (audio, _) = makeAudio()
        #expect(audio.isSoundOn)
        audio.isSoundOn = false
        #expect(!makeAudio().0.isSoundOn)
    }

    @Test func musicIsOnByDefaultAndTheSettingIsRemembered() {
        let (audio, _) = makeAudio()
        #expect(audio.isMusicOn)
        audio.isMusicOn = false
        let relaunched = makeAudio().0
        #expect(!relaunched.isMusicOn)
        #expect(relaunched.isSoundOn)
    }

    /// 1.0's one switch silenced the music too, so an install that turned it off stays silent after
    /// the update, and the music stays off once the sound comes back on.
    @Test func anOldSaveWithSoundOffKeepsTheMusicOff() {
        defaults.set(false, forKey: "mathReef.soundOn")
        let (audio, _) = makeAudio()
        #expect(!audio.isSoundOn)
        #expect(!audio.isMusicOn)

        audio.isSoundOn = true
        let relaunched = makeAudio().0
        #expect(relaunched.isSoundOn)
        #expect(!relaunched.isMusicOn)
    }

    @Test func anOldSaveWithSoundOnKeepsTheMusicOn() {
        defaults.set(true, forKey: "mathReef.soundOn")
        let (audio, _) = makeAudio()
        #expect(audio.isMusicOn)

        audio.isSoundOn = false
        #expect(makeAudio().0.isMusicOn)
    }

    @Test func starsRingOnSeparateVoicesSoTheyOverlap() {
        let (audio, voices) = makeAudio()
        audio.play(.star)
        audio.play(.star)
        #expect(voices("star").filter(\.isPlaying).count == 2)
    }

    @Test func turningSoundOffSilencesTheEffectsAtOnceAndLeavesTheMusic() async {
        let (audio, voices) = makeAudio()
        audio.play(.gulp)
        audio.playMusic(.menu, fade: 0)
        await settle()
        #expect(voices("gulp")[0].isPlaying && voices("menu-music")[0].isPlaying)

        audio.isSoundOn = false
        #expect(!voices("gulp")[0].isPlaying)
        #expect(voices("menu-music")[0].isPlaying)
        audio.play(.gulp)
        #expect(!voices("gulp")[0].isPlaying)
    }

    @Test func turningMusicOffSilencesTheMusicAtOnceAndLeavesTheEffects() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, fade: 0)
        await settle()
        audio.isMusicOn = false
        #expect(!voices("menu-music")[0].isPlaying)

        audio.play(.gulp)
        #expect(voices("gulp")[0].isPlaying)
        audio.playMusic(.game, fade: 0)
        await settle()
        #expect(!voices("game-music")[0].isPlaying)
    }

    @Test func musicBackOnResumesTheMusicTheCurrentScreenWants() async {
        let (audio, voices) = makeAudio()
        audio.isMusicOn = false
        audio.playMusic(.game, fade: 0)
        await settle()
        #expect(audio.currentMusic == .game)
        #expect(!voices("game-music")[0].isPlaying)

        audio.isMusicOn = true
        #expect(voices("game-music")[0].isPlaying)
        #expect(voices("game-music")[0].volume == ReefAudio.musicVolume)
    }

    @Test func switchingTracksPausesTheOldOne() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, fade: 0)
        await settle()
        audio.playMusic(.game, fade: 0)
        await settle()
        #expect(!voices("menu-music")[0].isPlaying)
        #expect(voices("game-music")[0].isPlaying)
    }

    @Test func movingBetweenMenusDoesNotRestartTheMusic() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, fade: 0)
        await settle()
        audio.playMusic(.menu, fade: 0)
        await settle()
        #expect(voices("menu-music")[0].playCount == 1)
    }

    @Test func aLaterChangeCancelsADelayedStart() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, after: 0.1, fade: 0)  // the jingle's wait before the map music
        audio.playMusic(nil, fade: 0)
        try? await Task.sleep(for: .milliseconds(500))
        #expect(!voices("menu-music")[0].isPlaying)
    }

    @Test func musicPausesInTheBackgroundAndResumesAfter() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, fade: 0)
        await settle()
        audio.pauseForBackground()
        #expect(!voices("menu-music")[0].isPlaying)
        audio.resumeFromBackground()
        #expect(voices("menu-music")[0].isPlaying)

        audio.isMusicOn = false
        audio.resumeFromBackground()
        #expect(!voices("menu-music")[0].isPlaying)
    }
}
