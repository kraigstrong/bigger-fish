import CoreGraphics
import FishKit
import Foundation
import Testing
@testable import MathReef

/// The first-launch tutorial: who sees it, and when each step is done. The steps run on the game's
/// real movement (`PlayerMotion` with `ReefTuning.motion`), frame by frame as the scene does.
struct TutorialTests {
    private typealias L = ReefTuning
    /// The iPhone 17's water in landscape, as the scene computes it.
    private let minY = L.waterBottomMargin + L.playerRadius * 0.95
    private let maxY = 402 - L.waterTopMargin - L.playerRadius * 0.95
    private let dt: CGFloat = 1 / 60

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "TutorialTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// The fish and the tutorial, one frame at a time.
    private struct Run {
        var flow = TutorialFlow()
        var y: CGFloat
        var vy: CGFloat = 0
        var events: [TutorialFlow.Event] = []
        var seconds: CGFloat = 0
    }

    /// Plays `seconds` of frames, holding whenever `holding` says so (given the time into this call),
    /// and stopping early once `until` is true.
    private func play(
        _ run: inout Run, seconds: CGFloat, holding: (CGFloat) -> Bool,
        until: (Run) -> Bool = { _ in false }
    ) {
        var t: CGFloat = 0
        while t < seconds, !until(run) {
            let hold = holding(t)
            (run.y, run.vy) = PlayerMotion.step(
                y: run.y, vy: run.vy, holding: hold, dt: dt, minY: minY, maxY: maxY, tuning: L.motion
            )
            if let event = run.flow.update(fishY: run.y, holding: hold, dt: dt, minY: minY, maxY: maxY) {
                run.events.append(event)
            }
            t += dt
            run.seconds += dt
        }
    }

    // MARK: Who sees it

    @Test func aFreshInstallPlaysItUntilItsFinishedOrSkipped() {
        withDefaults { defaults in
            let store = ProgressStore(defaults: defaults)
            #expect(!store.hasProgress)
            #expect(TutorialRecord(defaults: defaults).shouldPlayAtLaunch(hasProgress: store.hasProgress))
            // Closing the app partway isn't finishing it: it plays again next launch.
            #expect(TutorialRecord(defaults: defaults).shouldPlayAtLaunch(hasProgress: store.hasProgress))

            TutorialRecord(defaults: defaults).markDone()  // the first catch, or Skip
            let relaunched = TutorialRecord(defaults: defaults)
            #expect(relaunched.isDone)
            #expect(!relaunched.shouldPlayAtLaunch(hasProgress: false))
        }
    }

    /// Players updating from a version without the tutorial already know the controls. Their save
    /// has no tutorial flag, which must load as "not played", and their progress must be untouched.
    @Test func playersWithAnOlderSaveNeverSeeIt() throws {
        try withDefaults { defaults in
            let old = #"{"add.plus12":{"passed":true,"bestPercent":92},"add.make10":{"passed":false,"bestPercent":40}}"#
            defaults.set(Data(old.utf8), forKey: "mathReef.progress.v2")
            defaults.set(false, forKey: "mathReef.soundOn")
            #expect(defaults.object(forKey: TutorialRecord.key) == nil)

            let store = ProgressStore(defaults: defaults)
            #expect(store.hasProgress)
            let record = TutorialRecord(defaults: defaults)
            #expect(!record.isDone)
            #expect(!record.shouldPlayAtLaunch(hasProgress: store.hasProgress))

            // Marked done, so it stays away even if their progress is later cleared.
            #expect(record.isDone)
            #expect(!TutorialRecord(defaults: defaults).shouldPlayAtLaunch(hasProgress: false))

            let addition = try #require(Curriculum.worlds.first { $0.id == "addition" })
            let reloaded = ProgressStore(defaults: defaults)
            #expect(reloaded.record(for: addition.levels[0]) == LevelRecord(passed: true, bestPercent: 92, hasPlayed: false))
            #expect(reloaded.record(for: addition.levels[1]).bestPercent == 40)
        }
    }

    /// Only finished rounds count as progress; a changed setting alone doesn't.
    @Test func progressMeansAFinishedRound() {
        withDefaults { defaults in
            defaults.set(false, forKey: "mathReef.soundOn")
            let store = ProgressStore(defaults: defaults)
            #expect(!store.hasProgress)
            #expect(TutorialRecord(defaults: defaults).shouldPlayAtLaunch(hasProgress: store.hasProgress))

            let exponents = Curriculum.worlds.first { $0.id == "exponents" }!
            store.finishRound(0, in: exponents, correct: 2, attempts: 10)  // a round played, nothing passed
            #expect(store.hasProgress)
            #expect(ProgressStore(defaults: defaults).hasProgress)
        }
    }

    // MARK: Hold

    @Test func holdingLiftsTheFishAndMovesOnToLetGo() {
        var run = Run(y: minY)
        play(&run, seconds: 5, holding: { _ in true }, until: { $0.flow.step != .hold })
        #expect(run.flow.step == .letGo)
        #expect(run.events == [.began(.letGo)])
        #expect(run.y - minY >= (maxY - minY) * L.tutorialRiseFraction)
        // A kid who holds right away is through in under a second.
        #expect(run.seconds < 1)
    }

    /// Tapping (or tapping the fish) over and over never lifts it far enough: only holding does.
    /// The hint keeps coming back, and the step never fails or moves on by itself.
    @Test func tappingRepeatedlyDoesntCountAsHolding() {
        var run = Run(y: minY)
        play(&run, seconds: 30, holding: { $0.truncatingRemainder(dividingBy: 0.5) < 0.08 })
        #expect(run.flow.step == .hold)
        #expect(run.events.count >= 3 && run.events.allSatisfy { $0 == .hint })
    }

    @Test func aKidWhoDoesNothingSeesTheHintAgainAndNothingElse() {
        var run = Run(y: (minY + maxY) / 2)
        play(&run, seconds: 60, holding: { _ in false })
        #expect(run.flow.step == .hold)
        let expected = Int(60 / L.tutorialHintSeconds)
        #expect(abs(run.events.count - expected) <= 1)
        #expect(run.events.allSatisfy { $0 == .hint })
    }

    /// A hold that starts high can't rise far, but reaching the top counts.
    @Test func holdingUpToTheTopCounts() {
        var run = Run(y: maxY - 20)
        play(&run, seconds: 3, holding: { _ in true }, until: { $0.flow.step != .hold })
        #expect(run.flow.step == .letGo)
    }

    // MARK: Let go

    @Test func lettingGoSinksTheFishAndMovesOnToEat() {
        var run = Run(y: minY)
        play(&run, seconds: 5, holding: { _ in true }, until: { $0.flow.step != .hold })
        let high = run.y
        play(&run, seconds: 5, holding: { _ in false }, until: { $0.flow.step != .letGo })
        #expect(run.flow.step == .eat)
        #expect(run.events == [.began(.letGo), .began(.eat)])
        #expect(run.y < high)
        // The whole hold-and-let-go takes a quick kid under two seconds.
        #expect(run.seconds < 2)
    }

    /// Still holding after "Let go" appears: the lift-off hint plays again, and the step waits.
    @Test func keepingHoldingReplaysTheLetGoHint() {
        var run = Run(y: minY)
        play(&run, seconds: 5, holding: { _ in true }, until: { $0.flow.step != .hold })
        play(&run, seconds: 10, holding: { _ in true })
        #expect(run.flow.step == .letGo)
        #expect(run.events.first == .began(.letGo))
        #expect(run.events.dropFirst().count >= 2 && run.events.dropFirst().allSatisfy { $0 == .hint })
    }

    /// Pressing again partway down starts the sinking over: it has to be a real let-go.
    @Test func pressingAgainStartsTheSinkOver() {
        var run = Run(y: minY)
        play(&run, seconds: 5, holding: { _ in true }, until: { $0.y >= maxY })
        #expect(run.flow.step == .letGo)
        // Short drops between presses never sink the fish far enough.
        play(&run, seconds: 3, holding: { $0.truncatingRemainder(dividingBy: 0.3) > 0.1 })
        #expect(run.flow.step == .letGo)
        play(&run, seconds: 3, holding: { _ in false }, until: { $0.flow.step != .letGo })
        #expect(run.flow.step == .eat)
    }

    // MARK: Eat the answer

    private func atEat() -> TutorialFlow {
        var run = Run(y: minY)
        play(&run, seconds: 5, holding: { _ in true }, until: { $0.flow.step != .hold })
        play(&run, seconds: 5, holding: { _ in false }, until: { $0.flow.step != .letGo })
        return run.flow
    }

    @Test func theFirstCatchIsOnePlusOne() {
        #expect(TutorialFlow.fact.prompt == "1 + 1")
        #expect(TutorialFlow.fact.solution == "1 + 1 = 2")
        #expect(TutorialFlow.choices.filter(\.isCorrect).map(\.value) == [TutorialFlow.fact.answer])
        #expect(TutorialFlow.choices.filter { !$0.isCorrect }.map(\.value) == [3])
    }

    /// The 3 bounces off: no fail, the step stays, and the 2 can still be eaten.
    @Test func eatingTheWrongAnswerIsATryAgain() {
        var flow = atEat()
        #expect(flow.step == .eat)
        #expect(flow.ate(correct: false) == .tryAgain)
        #expect(flow.ate(correct: false) == .tryAgain)
        #expect(flow.step == .eat)
        #expect(flow.missed() == .hint)
        #expect(flow.ate(correct: true) == .began(.done))
        #expect(flow.step == .done)
        // Nothing more happens once it's over.
        #expect(flow.ate(correct: true) == nil)
        #expect(flow.missed() == nil)
    }

    /// Answers only count once the tutorial gets to them.
    @Test func eatingBeforeTheEatStepDoesNothing() {
        var flow = TutorialFlow()
        #expect(flow.ate(correct: true) == nil)
        #expect(flow.missed() == nil)
        #expect(flow.step == .hold)
    }

    /// The first 2 takes a hold to reach (the fish rests on the bottom after "Let go"); the 3 stays in
    /// the middle, out of a resting fish's way; and the next 2 comes along the bottom, so a kid who's
    /// stuck still makes the first catch.
    @Test func theFirstTwoTakesAHoldAndTheNextOneDoesnt() {
        let lanes = (0..<4).map(TutorialFlow.lanes(onPass:))
        let (bottom, middle, top) = (L.laneFractions[0], L.laneFractions[1], L.laneFractions[2])
        #expect(bottom < middle && middle < L.tutorialTopLane && L.tutorialTopLane < top)
        #expect(lanes.map(\.right) == [L.tutorialTopLane, bottom, L.tutorialTopLane, bottom])
        #expect(lanes.allSatisfy { $0.wrong == middle })

        // A fish resting on the bottom (or held at the top) can't touch the 3 as it passes.
        let reach = (L.playerRadius + L.answerRadius) * L.collisionScale + L.answerBobRange.lowerBound
        let threeY = minY + (maxY - minY) * lanes[0].wrong
        #expect(threeY - minY > reach && maxY - threeY > reach)
        // Holding at the top does reach the first 2; resting on the bottom reaches the second.
        #expect(maxY - (minY + (maxY - minY) * lanes[0].right) < reach - 2 * L.answerBobRange.lowerBound)
        #expect(minY + (maxY - minY) * lanes[1].right - minY < reach - 2 * L.answerBobRange.lowerBound)
        // The 2 and the 3 never overlap, even bobbing toward each other.
        let twoY = minY + (maxY - minY) * lanes[0].right
        #expect(twoY - threeY > 2 * (L.answerRadius * 1.15 + L.answerBobRange.lowerBound))
    }

    /// The first 2 passes clearly under "Eat the answer" (with its fin and bob), and a fish held at the
    /// top still catches it, on the iPhone 17 and on the shortest landscape iPhones (SE, mini).
    @Test func theFirstTwoPassesUnderTheCaption() {
        for height: CGFloat in [402, 375] {
            let minY = L.waterBottomMargin + L.playerRadius * 0.95
            let maxY = height - L.waterTopMargin - L.playerRadius * 0.95
            let twoY = minY + (maxY - minY) * TutorialFlow.lanes(onPass: 0).right
            let captionBottom = height - L.tutorialEatCaptionInset - L.tutorialCaptionFontSize / 2
            let fishTop = twoY + L.answerRadius * 1.15 + L.answerBobRange.lowerBound
            #expect(captionBottom - fishTop >= 8, "\(height)")
            let reach = (L.playerRadius + L.answerRadius) * L.collisionScale
            #expect(maxY - twoY < reach - L.answerBobRange.lowerBound, "\(height)")
        }
    }

    // MARK: Look

    @Test func captionsAreAFewShortWords() {
        let captions = [TutorialFlow.Step.hold, .letGo, .eat].compactMap(TutorialFlow.caption(for:))
        #expect(captions == ["Hold", "Let go", "Eat the answer"])
        #expect(captions.allSatisfy { $0.split(separator: " ").count <= 3 })
        #expect(TutorialFlow.caption(for: .done) == nil)
    }

    /// The finger presses on open water well away from the player fish: "anywhere" means anywhere.
    @Test func theFingerPressesAwayFromTheFish() {
        #expect(L.tutorialFingerSpot.x - L.playerScreenX >= 0.3)
    }
}
