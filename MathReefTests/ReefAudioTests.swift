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

/// The sound and music switches and the music handoffs between screens. Sounds play on the audio queue, so tests wait
/// for it (`waitForQueue`) before checking; music starts and fades later still, so tests pass no fade and give it a
/// moment (`settle`).
@MainActor
struct ReefAudioTests {
    private let defaults: UserDefaults

    init() {
        let name = "ReefAudioTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    /// With a `gate`, the audio queue stalls on loading the first sound until the gate opens (or 10 seconds pass), as a
    /// slow audio device would.
    private func makeAudio(gate: DispatchSemaphore? = nil) -> (ReefAudio, (String) -> [FakeVoice]) {
        final class Box { var voices: [String: [FakeVoice]] = [:] }
        let box = Box()
        let audio = ReefAudio(defaults: defaults) { name, _ in
            if let gate, box.voices.isEmpty { _ = gate.wait(timeout: .now() + 10) }
            let voice = FakeVoice()
            box.voices[name, default: []].append(voice)
            return voice
        }
        return (audio, { box.voices[$0] ?? [] })
    }

    private func settle(_ audio: ReefAudio) async {
        try? await Task.sleep(for: .milliseconds(200))  // generous for slow CI machines
        audio.waitForQueue()
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
        audio.waitForQueue()
        #expect(voices("star").filter(\.isPlaying).count == 2)
    }

    @Test func turningSoundOffSilencesTheEffectsAtOnceAndLeavesTheMusic() async {
        let (audio, voices) = makeAudio()
        audio.play(.gulp)
        audio.playMusic(.menu, fade: 0)
        await settle(audio)
        #expect(voices("gulp")[0].isPlaying && voices("menu-music")[0].isPlaying)

        audio.isSoundOn = false
        audio.waitForQueue()
        #expect(!voices("gulp")[0].isPlaying)
        #expect(voices("menu-music")[0].isPlaying)
        audio.play(.gulp)
        audio.waitForQueue()
        #expect(!voices("gulp")[0].isPlaying)
    }

    @Test func turningMusicOffSilencesTheMusicAtOnceAndLeavesTheEffects() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, fade: 0)
        await settle(audio)
        audio.isMusicOn = false
        audio.waitForQueue()
        #expect(!voices("menu-music")[0].isPlaying)

        audio.play(.gulp)
        audio.waitForQueue()
        #expect(voices("gulp")[0].isPlaying)
        audio.playMusic(.game, fade: 0)
        await settle(audio)
        #expect(!voices("game-music")[0].isPlaying)
    }

    @Test func musicBackOnResumesTheMusicTheCurrentScreenWants() async {
        let (audio, voices) = makeAudio()
        audio.isMusicOn = false
        audio.playMusic(.game, fade: 0)
        await settle(audio)
        #expect(audio.currentMusic == .game)
        #expect(!voices("game-music")[0].isPlaying)

        audio.isMusicOn = true
        audio.waitForQueue()
        #expect(voices("game-music")[0].isPlaying)
        #expect(voices("game-music")[0].volume == ReefAudio.musicVolume)
    }

    @Test func switchingTracksPausesTheOldOne() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, fade: 0)
        await settle(audio)
        audio.playMusic(.game, fade: 0)
        await settle(audio)
        #expect(!voices("menu-music")[0].isPlaying)
        #expect(voices("game-music")[0].isPlaying)
    }

    @Test func movingBetweenMenusDoesNotRestartTheMusic() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, fade: 0)
        await settle(audio)
        audio.playMusic(.menu, fade: 0)
        await settle(audio)
        #expect(voices("menu-music")[0].playCount == 1)
    }

    @Test func aLaterChangeCancelsADelayedStart() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, after: 0.1, fade: 0)  // the jingle's wait before the map music
        audio.playMusic(nil, fade: 0)
        try? await Task.sleep(for: .milliseconds(500))
        audio.waitForQueue()
        #expect(!voices("menu-music")[0].isPlaying)
    }

    @Test func musicPausesInTheBackgroundAndResumesAfter() async {
        let (audio, voices) = makeAudio()
        audio.playMusic(.menu, fade: 0)
        await settle(audio)
        audio.pauseForBackground()
        audio.waitForQueue()
        #expect(!voices("menu-music")[0].isPlaying)
        audio.resumeFromBackground()
        audio.waitForQueue()
        #expect(voices("menu-music")[0].isPlaying)

        audio.isMusicOn = false
        audio.resumeFromBackground()
        audio.waitForQueue()
        #expect(!voices("menu-music")[0].isPlaying)
    }

    /// Starting a sound or music can block on the audio device, so nothing the scene calls from its frame loop waits
    /// for the queue: here it's stuck loading the sounds, and every call still returns at once.
    @Test func callsFromTheMainThreadDoNotWaitForTheQueue() {
        let gate = DispatchSemaphore(value: 0)
        let clock = ContinuousClock()
        let started = clock.now
        let (audio, voices) = makeAudio(gate: gate)
        audio.isSoundOn = false
        audio.isSoundOn = true
        audio.isMusicOn = false
        audio.isMusicOn = true
        audio.play(.gulp)
        audio.playMusic(.menu, fade: 0)
        audio.pauseForBackground()
        audio.resumeFromBackground()
        #expect(clock.now - started < .seconds(2))
        #expect(voices("gulp").isEmpty)

        gate.signal()
        audio.waitForQueue()
        #expect(voices("gulp")[0].isPlaying)
    }

    /// The switches take effect in the order they were flipped, even when the queue is behind.
    @Test func switchesFlippedWhileTheQueueIsBehindStillGateWhatPlays() async {
        let gate = DispatchSemaphore(value: 0)
        let (audio, voices) = makeAudio(gate: gate)
        audio.play(.gulp)
        audio.isSoundOn = false
        audio.play(.wrong)
        audio.isMusicOn = false
        audio.playMusic(.menu, fade: 0)
        #expect(!audio.isSoundOn && !audio.isMusicOn)
        #expect(audio.currentMusic == .menu)

        gate.signal()
        await settle(audio)
        #expect(!voices("gulp")[0].isPlaying)
        #expect(voices("wrong")[0].playCount == 0)
        #expect(!voices("menu-music")[0].isPlaying)

        audio.isMusicOn = true
        audio.waitForQueue()
        #expect(voices("menu-music")[0].isPlaying)
    }

    /// A store capture rebuilds the preview's soundtrack from these cues, so each is stamped with the game's clock when
    /// the scene asks for it, not when the queue gets to it.
    @Test func cuesAreStampedWhenTheyAreAskedFor() {
        let gate = DispatchSemaphore(value: 0)
        let (audio, _) = makeAudio(gate: gate)
        var cues: [(at: TimeInterval, cue: String)] = []
        audio.captureCues = { cues.append((at: $0, cue: $1)) }
        let playClock = StoreCapture.playClock
        defer { StoreCapture.playClock = playClock }

        StoreCapture.playClock = 10
        let askedAt = StoreCapture.now()
        audio.play(.mapJingle)
        audio.playMusic(.menu, after: 3.0, fade: 1.5)
        StoreCapture.playClock = 20
        gate.signal()
        audio.waitForQueue()
        #expect(cues.map(\.at) == [askedAt, askedAt])
        #expect(cues.map(\.cue) == ["sound map-jingle", "music menu-music 3.0 1.5"])

        // Sound off logs no sound cues; music changes are logged either way, as the screen still wants the track.
        audio.isSoundOn = false
        audio.isMusicOn = false
        audio.play(.gulp)
        audio.playMusic(.game, fade: 0)
        #expect(cues.map(\.cue).last == "music game-music 0.0 0.0")
        #expect(cues.count == 3)
    }
}
