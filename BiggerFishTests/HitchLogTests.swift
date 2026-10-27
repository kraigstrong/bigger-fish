#if DEBUG
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The Xcode-only hitch log (`HitchLog`): slow frames anywhere, where they happened, and what happened just before.
@MainActor
struct HitchLogTests {
    /// A log on a clock the test moves, keeping what it writes.
    private final class Harness {
        var clock: CFTimeInterval = 100
        var written: [[String: Any]] = []
        lazy var log = HitchLog(now: { [unowned self] in self.clock }) { [unowned self] in self.written.append($0) }
    }

    private static let frame120 = 1.0 / 120

    // MARK: The ring buffer

    @Test func theRingBufferKeepsTheLatestNewestFirst() {
        var ring = RingBuffer<Int>(capacity: 3)
        #expect(ring.newestFirst.isEmpty && ring.newest == nil && ring.count == 0)
        ring.append(1)
        ring.append(2)
        #expect(ring.newestFirst == [2, 1] && ring.newest == 2)
        for value in 3...7 { ring.append(value) }
        #expect(ring.newestFirst == [7, 6, 5] && ring.count == 3 && ring.newest == 7)
        ring.removeAll()
        #expect(ring.newestFirst.isEmpty && ring.newest == nil)
        ring.append(8)
        #expect(ring.newestFirst == [8])

        var single = RingBuffer<String>(capacity: 1)
        single.append("a")
        single.append("b")
        #expect(single.newestFirst == ["b"])
    }

    @Test func theLogKeepsOnlyItsLatestEvents() {
        let harness = Harness()
        for index in 0..<(HitchLog.eventCapacity + 5) {
            harness.clock += 0.01
            harness.log.note(.sound, index.isMultiple(of: 2) ? "eat" : "bounce")
        }
        #expect(harness.log.events.count == HitchLog.eventCapacity)
        #expect(harness.log.events.newest?.at == harness.clock)
    }

    // MARK: Where it happened

    /// The SwiftUI screen, until a scene comes up and says more about itself; only that scene can change or end its
    /// account, and when it leaves, the screen under it is back.
    @Test func aSceneSaysWhereItIsUntilItLeaves() {
        let harness = Harness(), log = harness.log
        #expect(log.context == HitchContext(.launch))
        log.show(HitchContext(.levelMap, detail: "kelp-forest"))
        #expect(log.context == HitchContext(.levelMap, detail: "kelp-forest"))
        let level = NSObject(), other = NSObject()
        log.enterScene(level, HitchContext(.level, detail: "kelp-forest.3", phase: "ready"), framesPerSecond: 120, screenMaximum: 120)
        #expect(log.context == HitchContext(.level, detail: "kelp-forest.3", phase: "ready"))
        log.updateScene(level, HitchContext(.level, detail: "kelp-forest.3", phase: "playing"))
        log.updateScene(other, HitchContext(.credits))
        log.leaveScene(other)
        #expect(log.context.phase == "playing" && log.context.screen == .level)
        log.leaveScene(level)
        #expect(log.context == HitchContext(.levelMap, detail: "kelp-forest"))
        // Showing the same screen again isn't news; each new one is.
        log.show(HitchContext(.levelMap, detail: "kelp-forest"))
        log.show(HitchContext(.worldMap))
        #expect(log.events.newestFirst.map(\.kind) == [.screen, .scene, .screen])
        #expect(log.events.newestFirst.map(\.detail) == ["world_map", "level", "level_map"])
        #expect(HitchContext(.level, detail: "kelp-forest.3", phase: "lost").fields as? [String: String]
                == ["screen": "level", "detail": "kelp-forest.3", "phase": "lost"])
        #expect(HitchContext(.settings).fields as? [String: String] == ["screen": "settings"])
    }

    /// A level says which level it is and its phase as it goes (pause and resume noted as such); the tutorial says its
    /// beat. Each notes what happens in it: the card, the swallow, the death, the result.
    @Test func aLevelKeepsItsPhaseAndNotesWhatHappens() {
        let harness = Harness()
        let scene = GameScene(world: .jellyBloom, levelIndex: 2)
        scene.hitchLog = harness.log
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        defer { withExtendedLifetime(view) {} }
        #expect(harness.log.context == HitchContext(.level, detail: "jelly-bloom.3", phase: "ready"))
        scene.debugStart()
        #expect(harness.log.context.phase == "playing")
        scene.debugPauseForTuning()
        #expect(harness.log.context.phase == "paused")
        scene.debugResume()
        scene.debugCommitFatalSwallowForMetrics()
        scene.debugAdvance(seconds: 1.5)
        #expect(harness.log.context == HitchContext(.level, detail: "jelly-bloom.3", phase: "lost"))
        let noted = harness.log.events.newestFirst.reversed().map { "\($0.kind.rawValue) \($0.detail)" }
        func order(_ entries: [String]) -> Bool {
            let found = entries.compactMap { entry in noted.firstIndex(of: entry) }
            return found.count == entries.count && found == found.sorted()
        }
        #expect(order(["scene level", "card ready card", "phase playing", "pause ", "resume ", "swallow you're eaten",
                       "death eaten", "phase lost", "result lost"]), "noted \(noted)")

        let tutorial = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: .adventure)
        tutorial.hitchLog = harness.log
        view.presentScene(tutorial)
        #expect(harness.log.context == HitchContext(.tutorial, detail: "holdToRise", phase: "ready"))
        tutorial.debugStartTutorial(at: .eatEnough)
        #expect(harness.log.context == HitchContext(.tutorial, detail: "eatEnough", phase: "playing"))
    }

    /// A planner study or bot plays a level with no screen: nothing it does is noted.
    @Test func aHeadlessStudyNotesNothing() {
        let harness = Harness()
        let scene = GameScene(world: .shallowReef, levelIndex: 4)
        scene.hitchLog = harness.log
        _ = scene.debugSimulate(policy: .collector, limit: 5)
        #expect(harness.log.events.count == 0)
    }

    /// The credits: the start card, the swim from the first tap, and the end card.
    @Test func theCreditsSayWhichCardOrTheSwim() {
        let harness = Harness()
        let settings = ArcadeSettings(defaults: UserDefaults(suiteName: "biggerFish.tests.hitches")!)
        settings.soundEffectsOn = false
        let scene = CreditsScene(reduceMotion: false, settings: settings)
        scene.hitchLog = harness.log
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        defer { withExtendedLifetime(view) {} }
        #expect(harness.log.context == HitchContext(.credits, phase: "start_card"))
        scene.debugAdvance(seconds: 0.1)
        #expect(harness.log.context == HitchContext(.credits, phase: "swimming"))
        scene.debugPlay()
        #expect(harness.log.context == HitchContext(.credits, phase: "end_card"))
        let cards = harness.log.events.newestFirst.filter { $0.kind == .card }.map(\.detail)
        #expect(cards.first == "credits end card" && cards.contains("thanks line"))
    }

    // MARK: Slow frames

    @Test func aFramesIntervalFollowsTheViewTheScreenAndLowPowerMode() {
        #expect(HitchLog.frameInterval(preferred: 120, screenMaximum: 120, lowPower: false) == 1.0 / 120)
        #expect(HitchLog.frameInterval(preferred: 120, screenMaximum: 60, lowPower: false) == 1.0 / 60)
        #expect(HitchLog.frameInterval(preferred: 30, screenMaximum: 120, lowPower: false) == 1.0 / 30)
        #expect(HitchLog.frameInterval(preferred: 120, screenMaximum: 120, lowPower: true) == 1.0 / 60)
        #expect(HitchLog.frameInterval(preferred: 0, screenMaximum: 0, lowPower: false) == 1.0 / 60)
    }

    /// A frame of 1.5 intervals or more is a hitch, recorded with where it happened, its timing (the main thread's
    /// longest stretch of work, and the scene's own update before it), and what happened just before, newest first.
    @Test func aSlowSceneFrameIsRecordedWithItsContextTimingAndEvents() throws {
        let harness = Harness(), log = harness.log
        let owner = NSObject()
        log.enterScene(owner, HitchContext(.level, detail: "shallow-reef.4", phase: "playing"), framesPerSecond: 120, screenMaximum: 120)
        var timestamp = 50.0
        func frame(after seconds: Double, update: Double = 0.002) {
            timestamp += seconds
            harness.clock += seconds
            log.frameBegan(owner, timestamp: timestamp)
            harness.clock += update
            log.frameEnded(owner)
            harness.clock -= update
        }
        frame(after: 0)
        // On time, and the jitter of a frame a little late, aren't hitches.
        frame(after: Self.frame120)
        frame(after: Self.frame120 * 1.4)
        #expect(harness.written.isEmpty)

        let lastFrame = harness.clock
        harness.clock += 0.001
        log.note(.swallow, "you're eaten")
        harness.clock += 0.004
        log.note(.haptic, "eaten: heavy impact + error notification")
        // The main thread works 21 ms without a break, then sleeps.
        log.mainThreadWoke()
        harness.clock += 0.021
        log.mainThreadSleeps()
        // The next frame comes 30 ms after the last.
        harness.clock = lastFrame
        frame(after: 0.030, update: 0.004)
        let hitch = try #require(harness.written.first)
        #expect(harness.written.count == 1)
        #expect(hitch["screen"] as? String == "level" && hitch["detail"] as? String == "shallow-reef.4")
        #expect(hitch["phase"] as? String == "playing" && hitch["source"] as? String == "scene")
        #expect(hitch["elapsedMs"] as? Double == 30)
        #expect(hitch["intervalMs"] as? Double == 8.3)
        #expect(hitch["missedFrames"] as? Int == 3)
        #expect(hitch["workMs"] as? Double == 21)
        #expect(hitch["updateMs"] as? Double == 2)
        let events = try #require(hitch["events"] as? [[String: Any]])
        #expect(events.compactMap { $0["event"] as? String }.prefix(2) == ["haptic", "swallow"])
        #expect(events.first?["detail"] as? String == "eaten: heavy impact + error notification")
        #expect(events.first?["agoMs"] as? Double == 25)
        #expect(events.dropFirst().first?["agoMs"] as? Double == 29)
        #expect(events.contains { $0["event"] as? String == "scene" })
        // The next frame's update is this one's.
        frame(after: 0.020, update: 0.001)
        #expect(harness.written.last?["updateMs"] as? Double == 4)
    }

    /// Events from long before a hitch aren't its story.
    @Test func onlyRecentEventsComeWithAHitch() throws {
        let harness = Harness(), log = harness.log
        log.note(.music, "menu-music")
        harness.clock += HitchLog.eventWindow + 1
        log.note(.screen, "settings")
        log.displayFrame(timestamp: 10, interval: Self.frame120)
        log.displayFrame(timestamp: 10.05, interval: Self.frame120)
        let events = try #require(harness.written.first?["events"] as? [[String: Any]])
        #expect(events.compactMap { $0["event"] as? String } == ["screen"])
    }

    /// The display link times frames only while no scene times its own, and never across a trip to the background.
    @Test func displayFramesCountWithoutASceneAndNotAcrossTheBackground() {
        let harness = Harness(), log = harness.log
        log.show(HitchContext(.settings))
        log.displayFrame(timestamp: 1, interval: Self.frame120)
        log.displayFrame(timestamp: 1.1, interval: Self.frame120)
        #expect(harness.written.count == 1)
        #expect(harness.written.first?["screen"] as? String == "settings" && harness.written.first?["source"] as? String == "display")
        #expect(harness.written.first?["updateMs"] == nil)

        let owner = NSObject()
        log.enterScene(owner, HitchContext(.credits, phase: "start_card"), framesPerSecond: 120, screenMaximum: 120)
        log.displayFrame(timestamp: 2, interval: Self.frame120)
        log.displayFrame(timestamp: 3, interval: Self.frame120)
        #expect(harness.written.count == 1)
        // The scene's first frame comes on time after the last one shown (a slow handoff is a hitch of its own).
        log.frameBegan(owner, timestamp: 1.1 + Self.frame120)
        log.resignActive()
        log.frameBegan(owner, timestamp: 9)
        log.becomeActive()
        log.frameBegan(owner, timestamp: 20)
        #expect(harness.written.count == 1)
        log.frameBegan(owner, timestamp: 20.1)
        #expect(harness.written.count == 2 && harness.written.last?["phase"] as? String == "start_card")
        // A frame from a scene that isn't up (one leaving as another comes) isn't timed.
        log.frameBegan(NSObject(), timestamp: 30)
        #expect(harness.written.count == 2)
    }

    /// Building and presenting a scene, and leaving it, are timed: the first frame of each source times from the
    /// other's last, so a slow handoff is a hitch rather than a gap between two clocks.
    @Test func sceneHandoffsAreTimed() {
        let harness = Harness(), log = harness.log
        log.show(HitchContext(.levelMap))
        log.displayFrame(timestamp: 1, interval: Self.frame120)
        let owner = NSObject()
        log.enterScene(owner, HitchContext(.level, phase: "ready"), framesPerSecond: 120, screenMaximum: 120)
        log.frameBegan(owner, timestamp: 1.3)
        #expect(harness.written.count == 1)
        #expect(harness.written.last?["screen"] as? String == "level" && harness.written.last?["source"] as? String == "scene")
        log.frameBegan(owner, timestamp: 1.3 + Self.frame120)
        log.leaveScene(owner)
        log.displayFrame(timestamp: 1.5, interval: Self.frame120)
        #expect(harness.written.count == 2 && harness.written.last?["source"] as? String == "display")
    }

    /// The Tuning sheet over a level speaks for the screen while it's up: the display link times its frames, and the
    /// level underneath doesn't. When it goes, the level times its frames again, from the sheet's last.
    @Test func aSheetOverASceneTakesOverTheTiming() {
        let harness = Harness(), log = harness.log
        let owner = NSObject()
        log.show(HitchContext(.level))
        log.enterScene(owner, HitchContext(.level, phase: "paused"), framesPerSecond: 120, screenMaximum: 120)
        log.frameBegan(owner, timestamp: 1)
        log.show(HitchContext(.tuning))
        #expect(log.context.screen == .tuning)
        log.frameBegan(owner, timestamp: 5)
        #expect(harness.written.isEmpty)
        log.displayFrame(timestamp: 1 + Self.frame120, interval: Self.frame120)
        log.displayFrame(timestamp: 1.2, interval: Self.frame120)
        #expect(harness.written.count == 1 && harness.written.last?["screen"] as? String == "tuning")
        log.show(HitchContext(.level))
        #expect(log.context.screen == .level && log.context.phase == "paused")
        log.frameBegan(owner, timestamp: 1.2 + Self.frame120)
        #expect(harness.written.count == 1)
    }

    /// A long run of slow frames writes at most `hitchesPerSecond` a second; the next one counts the rest.
    @Test func aBurstOfSlowFramesIsCappedAndCounted() {
        let harness = Harness(), log = harness.log
        var timestamp = 0.0
        log.displayFrame(timestamp: timestamp, interval: Self.frame120)
        for _ in 0..<30 {
            timestamp += 0.02
            harness.clock += 0.02
            log.displayFrame(timestamp: timestamp, interval: Self.frame120)
        }
        #expect(harness.written.count == HitchLog.hitchesPerSecond)
        #expect(harness.written.allSatisfy { $0["suppressed"] == nil })
        timestamp += 0.5
        harness.clock += 0.5
        log.displayFrame(timestamp: timestamp, interval: Self.frame120)
        #expect(harness.written.last?["suppressed"] as? Int == 30 - HitchLog.hitchesPerSecond)
    }

    /// While a level's run is recording, its hitches go into that recording rather than the log's own file.
    @Test func aRecordedRunTakesItsOwnHitches() {
        let harness = Harness(), log = harness.log
        var inRun: [[String: Any]] = []
        log.runRecording = { inRun.append($0) }
        log.displayFrame(timestamp: 0, interval: Self.frame120)
        log.displayFrame(timestamp: 0.1, interval: Self.frame120)
        #expect(inRun.count == 1 && harness.written.isEmpty)
        log.runRecording = nil
        log.displayFrame(timestamp: 0.2, interval: Self.frame120)
        #expect(inRun.count == 1 && harness.written.count == 1)
    }
}
#endif
