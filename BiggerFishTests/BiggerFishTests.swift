import CoreGraphics
import Testing
@testable import BiggerFish

struct WrappedWorldTests {
    let world = WrappedWorld(width: 1000)

    @Test func wrapsIntoRange() {
        #expect(world.wrap(1010) == 10)
        #expect(world.wrap(-10) == 990)
        #expect(world.wrap(1000) == 0)
        #expect(world.wrap(0) == 0)
    }

    @Test func shortestDeltaCrossesSeam() {
        #expect(world.delta(from: 990, to: 10) == 20)
        #expect(world.delta(from: 10, to: 990) == -20)
        #expect(world.delta(from: 100, to: 300) == 200)
        #expect(world.delta(from: 300, to: 100) == -200)
    }

    @Test func distanceCrossesSeam() {
        let d = world.distance(CGPoint(x: 995, y: 0), CGPoint(x: 5, y: 0))
        #expect(abs(d - 10) < 1e-9)
        let diagonal = world.distance(CGPoint(x: 997, y: 0), CGPoint(x: 1, y: 3))
        #expect(abs(diagonal - 5) < 1e-9)
    }
}

struct SizeRuleTests {
    @Test func largerFishEats() {
        #expect(GameRules.encounter(20, 10) == .firstEatsSecond)
        #expect(GameRules.encounter(10, 20) == .secondEatsFirst)
    }

    @Test func nearEqualBumpsInsteadOfEating() {
        #expect(GameRules.encounter(10, 10) == .tooClose)
        #expect(GameRules.encounter(100, 99.5) == .tooClose)
        #expect(GameRules.encounter(99.5, 100) == .tooClose)
        #expect(GameRules.encounter(100, 98.9) == .firstEatsSecond)
        #expect(GameRules.encounter(98.9, 100) == .secondEatsFirst)
    }

    @Test func growthConservesArea() {
        #expect(abs(GameRules.grownRadius(predator: 3, prey: 4, efficiency: 1) - 5) < 1e-9)
        #expect(abs(GameRules.grownRadius(predator: 10, prey: 10, efficiency: 0.9) - 190.0.squareRoot()) < 1e-9)
    }

    @Test func closeSwallowsTakeLonger() {
        #expect(abs(GameRules.swallowDuration(sizeRatio: 0.3) - 0.12) < 1e-9)
        #expect(abs(GameRules.swallowDuration(sizeRatio: 0.75) - 0.30) < 1e-9)
        #expect(GameRules.swallowDuration(sizeRatio: 0.97) > 0.65)
        #expect(GameRules.swallowDuration(sizeRatio: 0.9) > GameRules.swallowDuration(sizeRatio: 0.6))
    }
}

struct WinStateTests {
    private func makeFish(_ id: Int, player: Bool = false, state: FishState = .swimming) -> Fish {
        let f = Fish(id: id, isPlayer: player, position: .zero, radius: 10)
        f.state = state
        return f
    }

    @Test func winsWhenOnlyPlayerRemains() {
        #expect(GameRules.isWin([makeFish(0, player: true)]))
        #expect(GameRules.isWin([makeFish(0, player: true), makeFish(1, state: .removed)]))
    }

    @Test func notWinWhileOthersLive() {
        #expect(!GameRules.isWin([makeFish(0, player: true), makeFish(1)]))
        #expect(!GameRules.isWin([makeFish(0, player: true), makeFish(1, state: .beingSwallowed(predatorID: 0))]))
    }

    @Test func notWinWhenPlayerIsGone() {
        #expect(!GameRules.isWin([makeFish(0, player: true, state: .removed)]))
        #expect(!GameRules.isWin([makeFish(1)]))
    }
}
