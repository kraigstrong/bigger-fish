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

struct BloomChaseTests {
    @Test func predatorsCannotOutrunPlayerAtAnyZoom() {
        for zoom: CGFloat in [1, 0.7, 0.4] {
            let playerSpeed: CGFloat = 320 / zoom
            let velocity = GameRules.bloomChaseVelocity(offset: CGVector(dx: 800, dy: -800),
                                                       cruiseSpeed: 500, playerSpeed: playerSpeed, zoom: zoom)
            #expect(velocity.dx <= playerSpeed * 0.75)
            #expect(abs(velocity.dy) <= GameTuning.motion.maxRiseSpeed * 0.55 / zoom)
            #expect(velocity.dx < playerSpeed)
        }
    }

    @Test func interceptingFishSteerTowardPlayerWithoutSpeedBoost() {
        let velocity = GameRules.bloomChaseVelocity(offset: CGVector(dx: -200, dy: 100),
                                                   cruiseSpeed: 80, playerSpeed: 300, zoom: 1)
        #expect(velocity.dx < 0)
        #expect(velocity.dy > 0)
        #expect(abs(velocity.dx) < 300)
    }
}

struct BloomMealTests {
    private func fish(_ id: Int, radius: CGFloat, player: Bool = false) -> Fish {
        Fish(id: id, isPlayer: player, position: .zero, radius: radius)
    }

    @Test func wipedOutReefRequiresCompletedMeals() {
        let player = fish(0, radius: 16, player: true)
        #expect(!GameRules.isWin([player], mealsEaten: 0, requiredMeals: 8))
        #expect(!GameRules.isWin([player], mealsEaten: 7, requiredMeals: 8))
        #expect(GameRules.isWin([player], mealsEaten: 8, requiredMeals: 8))
        #expect(!GameRules.isWin([player, fish(1, radius: 8)], mealsEaten: 8, requiredMeals: 8))
    }

    @Test func refillsOnlyStalledEcosystems() {
        let player = fish(0, radius: 16, player: true)
        #expect(GameRules.needsFood([player], mealsEaten: 0, requiredMeals: 8))
        #expect(!GameRules.needsFood([player], mealsEaten: 8, requiredMeals: 8))
        #expect(!GameRules.needsFood([player], mealsEaten: 0, requiredMeals: 0))
        #expect(!GameRules.needsFood([player, fish(1, radius: 8)], mealsEaten: 0, requiredMeals: 8))
        #expect(GameRules.needsFood([player, fish(1, radius: 32)], mealsEaten: 8, requiredMeals: 8))
        player.state = .swallowing(preyID: 1)
        #expect(!GameRules.needsFood([player], mealsEaten: 7, requiredMeals: 8))
        player.state = .removed
        #expect(!GameRules.needsFood([player], mealsEaten: 0, requiredMeals: 8))
    }
}
