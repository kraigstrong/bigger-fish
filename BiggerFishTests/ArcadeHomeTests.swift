import Foundation
import Testing
@testable import BiggerFish

/// The home screen: Adventure's crowns and where it opens, what it tells a new player, and the Open Water's lines.
@MainActor
struct ArcadeHomeTests {
    private func fresh() -> ArcadeProgress {
        ArcadeProgress(defaults: UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!)
    }

    private func clearAll(_ world: ArcadeWorld, in progress: ArcadeProgress, deepEnd: Bool = false) {
        let count = deepEnd ? world.levelCount : min(world.levelCount, ArcadeWorld.mainLevelCount)
        for index in 0..<count { progress.clear(world, index, seconds: 30) }
    }

    /// A crown for each world: none until its ten levels are beaten, silver then, gold once its Deep End is too.
    @Test func eachWorldsCrownShowsHowMuchOfItIsBeaten() {
        let progress = fresh()
        #expect(ArcadeWorld.campaign.allSatisfy { progress.crown(in: $0, unlocked: true) == .none })
        for index in 0..<(ArcadeWorld.mainLevelCount - 1) { progress.clear(.shallowReef, index, seconds: 30) }
        #expect(progress.crown(in: .shallowReef, unlocked: true) == .none)
        progress.clear(.shallowReef, ArcadeWorld.mainLevelCount - 1, seconds: 30)
        #expect(progress.crown(in: .shallowReef, unlocked: true) == .silver)
        clearAll(.jellyBloom, in: progress, deepEnd: true)
        #expect(progress.crown(in: .jellyBloom, unlocked: true) == .gold)
        #expect(progress.crown(in: .kelpForest, unlocked: true) == .none)
    }

    /// Adventure opens the levels of the world you're on: the first with main levels left, else the last.
    @Test func adventureOpensTheWorldYoureOn() {
        let progress = fresh()
        #expect(ArcadeWorldMap.currentWorld(progress, unlocked: true) == .shallowReef)
        clearAll(.shallowReef, in: progress)
        #expect(ArcadeWorldMap.currentWorld(progress, unlocked: true) == ArcadeWorld.campaign[1])
        for world in ArcadeWorld.campaign { clearAll(world, in: progress) }
        #expect(ArcadeWorldMap.currentWorld(progress, unlocked: true) == ArcadeWorld.campaign.last)
    }

    /// Until Shallow Reef's first level is beaten, Adventure says to start there and how a level is won.
    @Test func aNewPlayerIsToldWhereToStartAndHowToWin() {
        let progress = fresh()
        #expect(ArcadeHome.isFirstTime(progress))
        #expect(ArcadeHome.winRule == "Eat every fish to win")
        progress.clear(.shallowReef, 0, seconds: 30)
        #expect(!ArcadeHome.isFirstTime(progress))
    }

    /// Before a run, the question the Open Water asks; after one, your best. Without the unlock, the day's runs left.
    @Test func openWaterSaysYourBestAndTheRunsLeft() {
        #expect(ArcadeHome.openWaterLines(best: 0, runsLeft: 5) == ["How far can you get?", "5 runs left today"])
        #expect(ArcadeHome.openWaterLines(best: 142, runsLeft: nil) == ["Best 142 fish"])
        #expect(ArcadeHome.openWaterLines(best: 142, runsLeft: 1) == ["Best 142 fish", "1 run left today"])
        #expect(ArcadeHome.openWaterLines(best: 9, runsLeft: 0) == ["Best 9 fish", "More runs tomorrow"])
    }
}
