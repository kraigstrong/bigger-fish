import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

@MainActor
struct ArcadeSimulationTests {
    @Test func growthPathMatchesTheNearEqualAndAreaRules() {
        #expect(ArcadeSimulation.hasGrowthPath(player: 16, radii: [12, 18, 24], efficiency: 0.78))
        #expect(!ArcadeSimulation.hasGrowthPath(player: 43.4, radii: [47.7, 50], efficiency: 0.78))
        #expect(!ArcadeSimulation.hasGrowthPath(player: 16, radii: [15.99], efficiency: 0.78))
    }
    @Test func identicalSimulationSeedsAndInputsRepeat() {
        let tuning = ArcadeTuning(level: GameTuning.bloomLevels[0])
        func run() -> ArcadeSimulation.Result {
            let scene = GameScene(size: CGSize(width: 874, height: 402), world: .jellyBloom)
            return scene.debugSimulate(candidate: "determinism", tuning: tuning, policy: .collector, seed: 0, limit: 5)
        }
        let first = run(), second = run()
        #expect(first.outcome == second.outcome)
        #expect(first.stats.playerMeals == second.stats.playerMeals)
        #expect(first.playerRadius == second.playerRadius)
        #expect(first.spawned == second.spawned)
    }

    @Test func ecologyProbeCannotDieOrFeed() {
        let scene = GameScene(size: CGSize(width: 874, height: 402), world: .jellyBloom, levelIndex: 1)
        let result = scene.debugSimulate(candidate: "ecology", tuning: ArcadeTuning(level: GameTuning.bloomLevels[1]),
            policy: .cautious, seed: 1, limit: 10, ecologyProbe: true)
        #expect(result.outcome == "timeout")
        #expect(result.stats.playerMeals == 0)
        #expect(result.seconds >= 10)
    }

    @Test func shippedEcosystemsKeepTheirFoodBudgetOnTwoScreenSizes() {
        for dimensions in [CGSize(width: 874, height: 402), CGSize(width: 667, height: 375)] {
            for (index, level) in GameTuning.bloomLevels.enumerated() {
                let scene = GameScene(size: dimensions, world: .jellyBloom, levelIndex: index)
                let result = scene.debugSimulate(candidate: "spawn budget", tuning: ArcadeTuning(level: level),
                    policy: .cautious, seed: 0, limit: 0)
                #expect(result.spawned == result.configured)
                #expect(result.initialGrowthPath)
            }
        }
    }

    @Test func skippedPassDoesNotAccidentallyCollectMeals() {
        let scene = GameScene(size: CGSize(width: 874, height: 402), world: .jellyBloom)
        let result = scene.debugSimulate(candidate: "skipped pass", tuning: ArcadeTuning(level: GameTuning.bloomLevels[0]),
            policy: .cautious, seed: 0, limit: 35, delayedPasses: 1)
        #expect(result.outcome == "won")
        #expect(!result.stats.mealStartLaps.isEmpty)
        #expect(result.stats.mealStartLaps.allSatisfy { $0 >= 1 })
    }

    @Test func everyShippedLevelHasAWinningRouteAtThreePhoneSizes() {
        for dimensions in [CGSize(width: 874, height: 402), CGSize(width: 852, height: 393), CGSize(width: 667, height: 375)] {
            for (index, level) in GameTuning.bloomLevels.enumerated() {
                let scene = GameScene(size: dimensions, world: .jellyBloom, levelIndex: index)
                let result = scene.debugSimulate(candidate: "winning route", tuning: ArcadeTuning(level: level),
                    policy: index == 4 ? .cautious : .opportunist, seed: 0, limit: 90)
                #expect(result.outcome == "won", "Level \(index + 1), width \(dimensions.width)")
                if index == 4 && dimensions.width == 874 {
                    #expect(result.stats.closeMeals >= 3)
                    #expect(result.stats.lastThreat / result.seconds > 0.6)
                }
            }
        }
    }

    /// Local-only batch, activated with a marker under ignored build/. CI skips it.
    @Test func manualStudy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let marker = root.appendingPathComponent("build/arcade-development/simulation-study-request.json")
        guard let data = try? Data(contentsOf: marker) else { return }
        struct Request: Codable {
            let candidates: [Candidate]
            let seeds: [Int]
            let policies: [ArcadeSimulation.Policy]
            let limit: Double
            let delayedPasses: [Double]
            let ecology: Bool
            let firstPassMealLimits: [Int]?
            let skippedFirstPassFishIDs: [[Int]]?
        }
        struct Candidate: Codable {
            let name: String
            let level: Int
            let tuning: ArcadeTuning
            let width: Double?
            let height: Double?
        }
        let request = try JSONDecoder().decode(Request.self, from: data)
        let output = root.appendingPathComponent("build/arcade-development/simulation-study-results.json")
        var results: [ArcadeSimulation.Result] = []
        for candidate in request.candidates {
            for seed in request.seeds {
                if request.ecology {
                    let scene = GameScene(size: CGSize(width: candidate.width ?? 874, height: candidate.height ?? 402), world: .jellyBloom, levelIndex: candidate.level - 1)
                    results.append(scene.debugSimulate(candidate: candidate.name, tuning: candidate.tuning, policy: .cautious,
                        seed: seed, limit: CGFloat(request.limit), ecologyProbe: true))
                }
                for policy in request.policies {
                    for delay in request.delayedPasses {
                        for skipped in request.skippedFirstPassFishIDs ?? [[]] {
                            for budget in request.firstPassMealLimits?.map { $0 < 0 ? nil : Optional.some($0) } ?? [nil] {
                                let scene = GameScene(size: CGSize(width: candidate.width ?? 874, height: candidate.height ?? 402), world: .jellyBloom, levelIndex: candidate.level - 1)
                                results.append(scene.debugSimulate(candidate: candidate.name, tuning: candidate.tuning, policy: policy,
                                    seed: seed, limit: CGFloat(request.limit), delayedPasses: CGFloat(delay),
                                    firstPassMealLimit: budget, skippedFirstPassFishIDs: skipped))
                            }
                        }
                    }
                }
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: output, options: .atomic)
            print("[SimulationStudy] \(candidate.name): \(results.count) rollouts written")
        }
        #expect(!results.isEmpty)
    }
}
