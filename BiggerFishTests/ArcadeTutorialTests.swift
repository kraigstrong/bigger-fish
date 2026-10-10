import CoreGraphics
import Foundation
import SpriteKit
import Testing
@testable import BiggerFish

/// The first-launch tutorial teaches the race: the sizes have to tell that story, and a player has to be able to
/// play it through quickly.
@MainActor
struct ArcadeTutorialTests {
    @Test func sizesTellTheRace() {
        typealias A = ArcadeTutorial
        let efficiency = A.level.effectiveAbsorptionEfficiency
        let afterFirst = A.radius(startingAt: .dodgeBigger)
        #expect(A.radius(startingAt: .eatSmaller) == GameTuning.baseRadius)
        // You can eat the first meal, not the big fish, and the missed fish while it passes you.
        #expect(GameRules.playerEncounter(GameTuning.baseRadius, A.firstMeal) == .firstEatsSecond)
        #expect(GameRules.playerEncounter(afterFirst, A.bigFish) == .secondEatsFirst)
        #expect(GameRules.playerEncounter(afterFirst, A.missedFish) == .firstEatsSecond)
        // It eats its two meals (they're smaller, not a near tie) and outgrows you.
        #expect(GameRules.encounter(A.missedFish, A.missedFishMeal) == .firstEatsSecond)
        #expect(GameRules.playerEncounter(afterFirst, A.missedFishGrown) == .secondEatsFirst)
        // One more meal and it's yours again.
        let last = A.lastMeal(you: afterFirst, rival: A.missedFishGrown)
        #expect(GameRules.playerEncounter(afterFirst, last) == .firstEatsSecond)
        let grown = GameRules.grownRadius(predator: afterFirst, prey: last, efficiency: efficiency)
        #expect(GameRules.playerEncounter(grown, A.missedFishGrown) == .firstEatsSecond)
        #expect(abs(A.missedFishGrown - 20.7) < 0.1 && grown > A.missedFishGrown)
    }

    @Test func pathsAreMeasuredFromYou() {
        let path = TutorialPath.headOn(share: 0.6, crossing: 1.6)
        #expect(path.at(0) == (0.78, 0.6))
        #expect(abs(path.at(1.6).ahead) < 0.001)
        #expect(path.at(99).ahead == -0.45 && path.at(99).share == 0.6)
        let turn = TutorialPath(points: [(0, 0, 0.2), (1, 1, 0.4)])
        #expect(abs(turn.at(0.5).ahead - 0.5) < 0.0001 && abs(turn.at(0.5).share - 0.3) < 0.0001)
    }

    @Test func onlyNewPlayersSeeItOnce() throws {
        func progress(_ json: String?) -> ArcadeProgress {
            let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
            if let json { defaults.set(Data(json.utf8), forKey: ArcadeProgress.key) }
            return ArcadeProgress(defaults: defaults)
        }
        let new = progress(nil)
        #expect(new.needsTutorial)
        new.sawTutorial()
        #expect(!new.needsTutorial && new.save.hasSeenTutorial == true)
        // A save from before the tutorial: someone who has cleared a level skips it; someone who hasn't sees it.
        #expect(!progress(#"{"clearedLevels":["shallow-reef.1"],"bestTimes":{},"hasSeenJellyLesson":false}"#).needsTutorial)
        #expect(progress(#"{"clearedLevels":[],"bestTimes":{},"hasSeenJellyLesson":false}"#).needsTutorial)
    }

    @Test func aPlayerFinishesItInUnderAMinute() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0, showsJellyLesson: false, tutorial: true)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        let run = scene.debugPlayTutorial()
        print("TUTORIAL finished=\(run.finished) seconds=\(String(format: "%.1f", run.seconds)) beats=\(run.beats.map { "\($0.beat)@\(String(format: "%.1f", $0.at))" })")
        #expect(run.finished, "beats reached: \(run.beats.map { "\($0.beat) at \(String(format: "%.1f", $0.at))" })")
        #expect(run.beats.map(\.beat) == ArcadeTutorial.Beat.allCases)
        #expect(run.seconds < 60)
        withExtendedLifetime(view) {}
    }
}
