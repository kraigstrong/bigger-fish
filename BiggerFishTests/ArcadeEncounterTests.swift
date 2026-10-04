import CoreGraphics
import FishKit
import SpriteKit
import Testing
@testable import BiggerFish

struct ArcadeEncounterTests {
    @MainActor @Test func protectedFishSeparateAndTurnAwayEvenAgainstReleasedPredators() {
        for index in [0, 1, 9] {
            let scene = GameScene(world: .jellyBloom, levelIndex: index)
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
            view.presentScene(scene)
            scene.debugStart()
            #expect(scene.debugProtectedFishYieldCheck())
            withExtendedLifetime(view) {}
        }
    }

    @MainActor @Test func campaignRoamsWithIndividualProtectionAndVariedJellyHeights() {
        #expect(GameTuning.bloomLevels[1].freeEncounterMovement)
        #expect(GameTuning.bloomLevels.allSatisfy { $0.freeEncounterMovement })
        #expect(GameTuning.bloomLevels[1].absorptionEfficiency < GameTuning.encounterAbsorption)
        let result = GameScene(world: .jellyBloom, levelIndex: 1).debugFreeEncounterMotionCheck()
        #expect(result.travel > 150)
        #expect(result.fastFish >= 3)
        #expect(result.intact)
        #expect(result.heightSpread > 70)
        #expect(result.individualReleases == 16)
    }

    @MainActor @Test func movementAvoidanceAllowsARealAIBellBounce() {
        let scene = GameScene(world: .jellyBloom, levelIndex: 1)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        view.presentScene(scene)
        scene.debugStart()
        #expect(scene.debugAIMovementAllowsBellLanding())
        withExtendedLifetime(view) {}
    }

    @MainActor @Test func evenProtectedAIFishCanBounceWithoutDyingFromStingers() {
        for index in [0, 1] {
            let scene = GameScene(world: .jellyBloom, levelIndex: index)
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
            view.presentScene(scene)
            scene.debugStart()
            #expect(scene.debugAIFallOntoDome())
            #expect(scene.debugTouchTentacles(playerVictim: false))
            #expect(scene.debugTouchTentacles(playerVictim: true))
            withExtendedLifetime(view) {}
        }
    }

    @Test func freeCampaignBudgetsRepeatVaryAndRequireIncreasingCatchPercentages() {
        var previous: CGFloat = 0
        var shapes = Set<String>()
        for index in 0..<10 {
            let difficulty = Double(index) / 9
            let fraction = GameTuning.freeEncounterExpectedCatchFraction(difficulty)
            #expect(fraction > previous)
            previous = fraction
            let seed = GameTuning.spawnSeed + UInt64(index + 100)
            let budgets = GameTuning.freeEncounterWaveBudgets(seed: seed, difficulty: difficulty, preserveLevelTwo: index == 1)
            #expect(budgets.reduce(0) { $0 + $1.count } == 16)
            #expect(budgets.allSatisfy { $0.edible >= 2 && $0.edible < $0.count })
            let shape = budgets.map { "\($0.edible)/\($0.count)" }.joined(separator: ",")
            shapes.insert(shape)
            #expect(shape == GameTuning.freeEncounterWaveBudgets(seed: seed, difficulty: difficulty, preserveLevelTwo: index == 1).map { "\($0.edible)/\($0.count)" }.joined(separator: ","))
            if index == 1 { #expect(shape == "3/4,2/3,3/5,3/4") }
        }
        #expect(shapes.count >= 5)
        #expect(abs(previous - 0.9) < 0.0001)
    }

    @Test func formationSeedsRepeatAndEveryWaveHasItsOwnShapeWithoutChangingFoodCount() {
        for seed: UInt64 in [0, 1, 33, 999] {
            let forms = GameTuning.encounterFormationOrder(seed: seed)
            #expect(forms.map(\.name) == GameTuning.encounterFormationOrder(seed: seed).map(\.name))
            #expect(forms.first?.name == "opening")
            #expect(Set(forms.map(\.name)).count == GameTuning.encounterCount)
            #expect(forms.allSatisfy { $0.foodOffsets.count == GameTuning.encounterFoodCount })
        }
        let orders = Set((0..<20).map { GameTuning.encounterFormationOrder(seed: UInt64($0)).map(\.name).joined(separator: ",") })
        #expect(orders.count > 1)
    }

    @MainActor @Test func variedWavesKeepTheirBudgetAndStartClearOfFishAndTentacles() {
        for index in 0..<10 {
            let scene = GameScene(world: .jellyBloom, levelIndex: index)
            #expect(scene.debugEncounterSpawnSafety(), "Level \(index + 1)")
        }
    }
    @Test func separationAnticipatesApproachesAndIgnoresDistantSwimmers() {
        let approaching = EncounterSteering.separation(relative: CGVector(dx: -80, dy: 0),
            velocity: CGVector(dx: 100, dy: 0), reach: 50, stableDirection: -1)
        #expect((approaching?.dx ?? 0) < 0)
        #expect(EncounterSteering.separation(relative: CGVector(dx: -80, dy: 0),
            velocity: CGVector(dx: -100, dy: 0), reach: 50, stableDirection: -1) == nil)
        #expect(EncounterSteering.separation(relative: CGVector(dx: -300, dy: 0),
            velocity: CGVector(dx: 100, dy: 0), reach: 50, stableDirection: -1) == nil)
        let overlap = EncounterSteering.separation(relative: .zero, velocity: .zero,
            reach: 50, stableDirection: 1)
        #expect((overlap?.dx ?? 0) > 0)
    }


    @Test func targetsScaleContinuouslyAndEveryCatchBudgetHasAGrowthRoute() {
        var previous: CGFloat = 0
        for index in 0...100 {
            let target = EncounterDifficulty(value: Double(index) / 100)
            let radius = target.returnRadius(food: GameTuning.encounterFoodRadius,
                efficiency: GameTuning.encounterAbsorption)
            #expect(radius > previous)
            previous = radius
            var player: CGFloat = 1
            for _ in 0..<target.minimumCatches {
                player = GameRules.grownRadius(predator: player, prey: GameTuning.encounterFoodRadius,
                    efficiency: GameTuning.encounterAbsorption)
            }
            #expect(GameRules.playerEncounter(player, radius) == .firstEatsSecond)
            #expect(target.spareCatches >= 1)
        }
        let easiest = EncounterDifficulty(value: 0), hardest = EncounterDifficulty(value: 1)
        #expect(easiest.minimumCatches == 4)
        #expect(hardest.minimumCatches == 11)
        #expect(easiest.recoveryPasses == 1)
        #expect(hardest.recoveryPasses == 0)
        #expect(easiest.clearance > hardest.clearance)
        #expect(EncounterDifficulty(value: .nan).bounded == 0)
    }

    @Test func protectionExpiresAtTheLocalDistanceBoundary() {
        let first = EncounterLease(home: .zero, releaseDistance: 100)
        let later = EncounterLease(home: .zero, releaseDistance: 300)
        #expect(first.isProtected(distance: 99.999))
        #expect(!first.isProtected(distance: 100))
        #expect(later.isProtected(distance: 100))
    }

    @MainActor @Test func scenePreservesFoodBeforeReleaseAndAllowsAICompetitionAfterIt() {
        for index in [0, 9] {
            let scene = GameScene(world: .jellyBloom, levelIndex: index)
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
            view.presentScene(scene)
            scene.debugStart()
            #expect(scene.debugEncounterProtectionLifecycle())
            withExtendedLifetime(view) {}
        }
    }
}
