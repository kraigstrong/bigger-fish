import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import MathReef

/// The screen changing size under the scene, as an iPhone Duo's does when it opens or closes: whatever was showing goes
/// on where it was, at the new size, and a round's next question waits for the kid's next hold. And a closed iPhone
/// Duo's camera, in a corner, moves the controls in that corner clear of it.
@MainActor
struct ScreenResizeTests {
    /// An iPhone Duo's screens in landscape, in points: closed, and open.
    private let closed = CGSize(width: 678, height: 466), open = CGSize(width: 951, height: 669)
    /// The closed screen's camera, in its top-left corner, as iOS 27.1 reports it.
    private var camera: CGRect { CGRect(x: 29, y: closed.height - 66, width: 37, height: 37) }

    private func world(_ id: String) -> Int { Curriculum.worlds.firstIndex { $0.id == id }! }

    /// The app's scene at `size`, on its own saved state, the reef unlocked, played a frame at a time.
    private func reef(_ size: CGSize) throws -> (DrawOrderTests.Stage, PracticeScene) {
        let suite = "mathReef.tests.screenResize"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: "mathReef.soundOn")
        defaults.set(true, forKey: "mathReef.unlocked")
        PracticeScene.testDefaults = defaults
        let scene = PracticeScene(size: size)
        return (try DrawOrderTests.Stage(scene), scene)
    }

    private func play(_ stage: DrawOrderTests.Stage, _ seconds: TimeInterval, until done: () -> Bool = { false }) {
        stage.play(seconds, "", until: done) { _, _, _ in }
    }

    private func expectSameSpots(_ before: [CGPoint], _ after: [CGPoint], _ comment: Comment) {
        #expect(before.count == after.count, comment)
        for (a, b) in zip(before, after) {
            #expect(abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001, comment)
        }
    }

    /// Opened mid-round, then closed again: the round goes on with the same question and score, your fish and the answers
    /// where they were in the water, standing still until the kid holds. Then it plays on to its results.
    @Test func aRoundGoesOnThroughOpeningAndClosing() throws {
        defer { PracticeScene.testDefaults = nil }
        let (stage, scene) = try reef(closed)
        scene.debugOpenLevel(world: world("addition"), level: 0)
        scene.debugStartRound()
        play(stage, 60) { scene.debugResult.correctAnswers >= 2 && scene.debugPhase == .answering }
        #expect(scene.debugPhase == .answering)

        for size in [open, closed] {
            let question = scene.debugQuestion, result = scene.debugResult, spots = scene.debugSpots
            scene.size = size
            #expect(scene.debugPhase == .answering)
            #expect(scene.debugQuestion == question)
            #expect(scene.debugResult == result)
            expectSameSpots(spots, scene.debugSpots, "moved in the water")

            scene.debugAutopilot = false
            play(stage, 3)
            #expect(scene.debugWaitingForHold)
            expectSameSpots(spots, scene.debugSpots, "moved before a hold")

            scene.debugHolding = true
            play(stage, 0.1)
            scene.debugHolding = false
            #expect(!scene.debugWaitingForHold)
            scene.debugAutopilot = true
            play(stage, 1)
        }
        play(stage, 120) { scene.debugPhase == .summary }
        #expect(scene.debugPhase == .summary, "The round didn't finish")
    }

    /// Opened while an answer's card shows: the card plays out, and the next question waits for a hold.
    @Test func anAnswersCardPlaysOutAndTheNextQuestionWaits() throws {
        defer { PracticeScene.testDefaults = nil }
        let (stage, scene) = try reef(closed)
        scene.debugOpenLevel(world: world("addition"), level: 0)
        scene.debugStartRound()
        play(stage, 30) { scene.debugPhase == .feedback }
        #expect(scene.debugPhase == .feedback)

        scene.size = open
        scene.debugAutopilot = false
        #expect(!scene.debugWaitingForHold)
        play(stage, 5) { scene.debugPhase == .answering }
        #expect(scene.debugPhase == .answering)
        play(stage, 2)
        #expect(scene.debugWaitingForHold)
    }

    /// The tutorial, opened partway: it keeps its step, and plays on to the reef.
    @Test func theTutorialKeepsItsStep() throws {
        defer { PracticeScene.testDefaults = nil }
        let (stage, scene) = try reef(closed)
        scene.debugStartTutorial()
        scene.debugAutopilot = true
        play(stage, 10) { scene.debugTutorialStep == .eat }
        #expect(scene.debugTutorialStep == .eat)

        scene.size = open
        #expect(scene.debugPhase == .tutorial)
        #expect(scene.debugTutorialStep == .eat)
        play(stage, 30) { scene.debugPhase == .home }
        #expect(scene.debugPhase == .home, "The tutorial didn't end on the reef")
    }

    /// A level's card, opened: as far across and up the screen as before, its button still under it.
    @Test func aCardKeepsItsPlaceAndItsButton() throws {
        defer { PracticeScene.testDefaults = nil }
        let (_, scene) = try reef(closed)
        scene.debugOpenLevel(world: world("addition"), level: 0)
        let before = scene.debugPanelFrame

        scene.size = open
        let card = scene.debugPanelFrame
        #expect(abs(card.midX / open.width - before.midX / closed.width) < 0.001)
        #expect(abs(card.midY / open.height - before.midY / closed.height) < 0.001)
        #expect(scene.debugButtonFrames.count == 1)
        for button in scene.debugButtonFrames {
            #expect(card.contains(CGPoint(x: button.midX, y: button.midY)))
        }
    }

    /// A level path with the parental gate open over it, a digit typed: opened, it's all still there.
    @Test func aMapAndTheScreenOverItStay() throws {
        defer { PracticeScene.testDefaults = nil }
        let (_, scene) = try reef(closed)
        scene.debugShow(.world(world("multiplication")))
        scene.debugShow(.parentalGate)
        scene.debugTypeGateAnswer(digits: 1)
        let entry = scene.debugGateEntry
        #expect(entry?.count == 1)

        scene.size = open
        #expect(scene.debugPhase == .world)
        #expect(scene.debugWorld == world("multiplication"))
        #expect(scene.debugSettingsShowing)
        #expect(scene.debugGateEntry == entry)
    }

    /// The closed screen's camera, in the top-left corner: a round's progress moves clear of it, and back when it goes
    /// (the phone turned around), without the round stopping to wait.
    @Test func theCornerControlsClearTheCamera() throws {
        defer { PracticeScene.testDefaults = nil }
        let (stage, scene) = try reef(closed)
        scene.debugOpenLevel(world: world("addition"), level: 0)
        scene.debugStartRound()
        play(stage, 1)
        let progress = scene.debugProgressLabel, settings = scene.debugSettingsButton

        scene.occlusions = [camera]
        #expect(scene.debugProgressLabel.x >= camera.maxX + ReefCorners.gap)
        #expect(scene.debugSettingsButton == settings)
        #expect(scene.debugPhase == .answering)
        #expect(!scene.debugWaitingForHold)

        scene.occlusions = []
        #expect(scene.debugProgressLabel == progress)
    }

    /// A camera in the top-right corner moves the settings button clear of it.
    @Test func theSettingsButtonClearsACameraOnItsSide() throws {
        defer { PracticeScene.testDefaults = nil }
        let (_, scene) = try reef(closed)
        scene.debugShow(.home)
        let topRight = CGRect(x: closed.width - camera.maxX, y: camera.minY, width: camera.width, height: camera.height)
        scene.occlusions = [topRight]
        #expect(scene.debugSettingsButton.x + 20 + ReefCorners.gap <= topRight.minX)
    }
}
