import CoreGraphics
import FishKit
import Testing
@testable import BiggerFish

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

    @Test func nearEqualEncountersFavorThePlayerInEitherOrder() {
        let pairs: [(CGFloat, CGFloat)] = [(10, 10), (100, 99.5), (99.5, 100)]
        for (player, other) in pairs {
            #expect(GameRules.encounter(player, other, firstIsPlayer: true) == .firstEatsSecond)
            #expect(GameRules.encounter(other, player, secondIsPlayer: true) == .secondEatsFirst)
        }
        #expect(GameRules.playerEncounter(98.9, 100) == .secondEatsFirst)
        #expect(GameRules.playerEncounter(100, 98.9) == .firstEatsSecond)
        #expect(GameRules.playerEncounter(0, 0) == .tooClose)
    }

    @Test func growthConservesArea() {
        #expect(abs(GameRules.grownRadius(predator: 3, prey: 4, efficiency: 1) - 5) < 1e-9)
        #expect(abs(GameRules.grownRadius(predator: 10, prey: 10, efficiency: 0.9) - 190.0.squareRoot()) < 1e-9)
    }

    @Test func closeSwallowsTakeLonger() {
        func duration(_ ratio: CGFloat) -> CGFloat {
            SwallowTiming.duration(sizeRatio: ratio, curve: GameTuning.swallowDurationCurve)
        }
        #expect(abs(duration(0.3) - 0.12) < 1e-9)
        #expect(abs(duration(0.75) - 0.30) < 1e-9)
        #expect(duration(0.97) > 0.65)
        #expect(duration(0.9) > duration(0.6))
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

struct BloomAvoidanceTests {
    private func avoid(_ position: CGPoint, _ velocity: CGVector, radius: CGFloat = 16) -> CGVector? {
        JellyRules.avoidance(at: position, velocity: velocity, fishRadius: radius,
                             domeRadius: 36, tentacleLength: 115, minY: -160, maxY: 130, zoom: 1)
    }

    @Test func seesCrossingAheadButLeavesSafeRoutesAlone() {
        let steering = avoid(CGPoint(x: -100, y: -40), CGVector(dx: 100, dy: 0))
        #expect(steering != nil)
        #expect((steering?.dy ?? 0) > 0)
        #expect(avoid(CGPoint(x: -100, y: 80), CGVector(dx: 100, dy: 0)) == nil)
        #expect(avoid(CGPoint(x: -100, y: -40), CGVector(dx: -100, dy: 0)) == nil)
        #expect(avoid(CGPoint(x: -400, y: -40), CGVector(dx: 100, dy: 0)) == nil)
    }

    @Test func bellLandingsTakePriorityWithoutDisablingStingerAvoidance() {
        #expect(avoid(CGPoint(x: 0, y: 80), CGVector(dx: 0, dy: -160)) == nil)
        #expect(avoid(CGPoint(x: -65, y: 90), CGVector(dx: 100, dy: -130)) == nil)
        #expect(avoid(CGPoint(x: -60, y: 33), CGVector(dx: 100, dy: 0)) == nil)
        #expect(avoid(CGPoint(x: 0, y: -80), CGVector(dx: 0, dy: 150)) != nil)
        #expect(avoid(CGPoint(x: -100, y: 35), CGVector(dx: 100, dy: -100)) != nil)
    }

    @Test func turnsAwayBeforeCurtainAndCanChooseBelow() {
        let close = avoid(CGPoint(x: -60, y: -40), CGVector(dx: 100, dy: 0))
        #expect((close?.dx ?? 0) < 0)
        let below = avoid(CGPoint(x: -100, y: -110), CGVector(dx: 100, dy: 0))
        #expect((below?.dy ?? 0) < 0)
        let giant = avoid(CGPoint(x: -100, y: -40), CGVector(dx: 100, dy: 0), radius: 50)
        #expect((giant?.dx ?? 0) < 0)
    }
}
