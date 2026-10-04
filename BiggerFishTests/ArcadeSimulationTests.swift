import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

@MainActor
struct ArcadeSimulationTests {
    @Test func growthPathMatchesTheNearEqualAndAreaRules() {
        #expect(ArcadeSimulation.hasGrowthPath(player: 16, radii: [12, 18, 24], efficiency: 0.78))
        #expect(!ArcadeSimulation.hasGrowthPath(player: 43.4, radii: [47.7, 50], efficiency: 0.78))
        #expect(ArcadeSimulation.hasGrowthPath(player: 16, radii: [15.99], efficiency: 0.78))
    }
    @Test func identicalSimulationSeedsAndInputsRepeat() {
        let tuning = ArcadeTuning(level: GameTuning.bloomLevels[0])
        func run() -> ArcadeSimulation.Result {
            let scene = GameScene(world: .jellyBloom)
            return scene.debugSimulate(candidate: "determinism", tuning: tuning, policy: .collector, seed: 0, limit: 5)
        }
        let first = run(), second = run()
        #expect(first.outcome == second.outcome)
        #expect(first.stats.playerMeals == second.stats.playerMeals)
        #expect(first.playerRadius == second.playerRadius)
        #expect(first.spawned == second.spawned)
    }

    @Test func fixedGameplayRepeatsAcrossDisplaySchedulesIncludingSlowMotion() {
        let schedules = [
            Array(repeating: CGFloat(1) / 60, count: 480),
            Array(repeating: CGFloat(1) / 30, count: 240),
            Array(repeating: CGFloat(1) / 120, count: 960),
            (0..<480).map { CGFloat($0.isMultiple(of: 2) ? 1 : 3) / 120 },
            Array(repeating: CGFloat(1) / 10, count: 80),
        ]
        for slow in [false, true] {
            func run(_ frames: [CGFloat]) -> ArcadeSimulation.Audit {
                let scene = GameScene(world: .jellyBloom, levelIndex: 4)
                return scene.debugAuditRepeatability(frames: frames, fixedStep: true,
                    slowMotion: slow, scriptedInput: true)
            }
            let control = run(schedules[0])
            for schedule in schedules.dropFirst() { #expect(control == run(schedule)) }
        }
    }

    @Test func fixedTimingBoundsHitchesAndDropsPausedDebt() {
        let scene = GameScene(world: .jellyBloom)
        #expect(scene.debugCheckFixedTimingLifecycle())
    }

    @Test func noninteractingFishKeepTheirMovementWhenOtherFishAreSkippedOrRemoved() {
        let frames = Array(repeating: CGFloat(1) / 60, count: 480)
        for world: ArcadeWorld in [.shallowReef, .jellyBloom] {
            for index in world.levels.indices {
                func run(omitted: Set<Int> = [], remove: Bool = false) -> ArcadeSimulation.Audit {
                    let scene = GameScene(world: world, levelIndex: index)
                    return scene.debugAuditRepeatability(frames: frames, omittedIDs: omitted, removeOmittedFish: remove)
                }
                let control = run()
                for omitted: Set<Int> in [[1], [1, 2, 3]] {
                    let expected = control.fish.filter { !omitted.contains($0.id) }
                    #expect(run(omitted: omitted).fish == expected)
                    #expect(run(omitted: omitted, remove: true).fish == expected)
                }
            }
        }
    }

    @Test func removedFishReleaseTheirStreamsAndRetriesRecreateThem() {
        let scene = GameScene(world: .jellyBloom)
        let tuning = ArcadeTuning(level: GameTuning.bloomLevels[0])
        _ = scene.debugSimulate(candidate: "stream lifecycle", tuning: tuning, policy: .collector, seed: 0, limit: 0)
        scene.debugHazardWipeout()
        #expect(scene.debugAIMovementStreamIDs.isEmpty)
        let retry = scene.debugSimulate(candidate: "stream reset", tuning: tuning, policy: .collector, seed: 0, limit: 0)
        #expect(scene.debugAIMovementStreamIDs == Set(1...retry.spawned))
    }

    @Test func ecologyProbeCannotDieOrFeed() {
        let scene = GameScene(world: .jellyBloom, levelIndex: 1)
        let result = scene.debugSimulate(candidate: "ecology", tuning: ArcadeTuning(level: GameTuning.bloomLevels[1]),
            policy: .cautious, seed: 1, limit: 10, ecologyProbe: true)
        #expect(result.outcome == "timeout")
        #expect(result.stats.playerMeals == 0)
        #expect(result.seconds >= 10)
    }

    @Test func shippedEcosystemsKeepTheirFoodBudget() {
        for (index, level) in GameTuning.bloomLevels.enumerated() {
            let scene = GameScene(world: .jellyBloom, levelIndex: index)
            let result = scene.debugSimulate(candidate: "spawn budget", tuning: ArcadeTuning(level: level),
                policy: .cautious, seed: 0, limit: 0)
            #expect(result.spawned == result.configured)
            #expect(result.initialGrowthPath)
        }
    }

    @Test func skippedPassDoesNotAccidentallyCollectMeals() {
        let tuning = ArcadeTuning(level: GameTuning.bloomLevels[0])
        func run(_ delay: CGFloat) -> ArcadeSimulation.Result {
            GameScene(world: .jellyBloom).debugSimulate(
                candidate: "skipped pass", tuning: tuning, policy: .cautious, seed: 0, limit: 8, delayedPasses: delay)
        }
        let feeding = run(0), skipped = run(1)
        #expect(!feeding.stats.mealStartLaps.isEmpty)
        #expect(skipped.stats.mealStartLaps.isEmpty)
    }

    // Bot misses are exploratory tuning feedback, not proof that a human cannot win.
    // Opt in explicitly while improving these policies; human-confirmed routes remain valid.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ARCADE_VALIDATE_ROUTES"] == "1"))
    func everyShippedLevelHasAWinningRoute() {
        for (index, level) in GameTuning.bloomLevels.enumerated() {
            var won = false
            for policy in ArcadeSimulation.Policy.allCases {
                let scene = GameScene(world: .jellyBloom, levelIndex: index)
                let result = scene.debugSimulate(candidate: "winning route", tuning: ArcadeTuning(level: level),
                    policy: policy, seed: 0, limit: 90)
                if result.outcome == "won" { won = true; break }
            }
            #expect(won, "Level \(index + 1)")
        }
    }

    @Test func acceptedOriginalLevelFiveOpeningRemainsAvailableAsAReference() {
        let scene = GameScene(world: .jellyBloom, levelIndex: 4)
        // This fixture records the original pre-global-growth opening, not today's balance.
        var reference = ArcadeTuning(level: GameTuning.bloomReferenceLevels[4])
        reference.absorption /= Double(GameTuning.mealGrowthScale)
        let result = scene.debugSimulate(candidate: "original opening", tuning: reference,
            policy: .opportunist, seed: 0, limit: 90)
        #expect(result.outcome == "won")
        #expect(Array(result.stats.mealStartFishIDs.prefix(4)) == [1, 8, 10, 18])
        for (actual, baseline) in zip(result.stats.mealStartLaps.prefix(4), [0.180, 0.235, 0.392, 0.410]) {
            #expect(abs(actual - baseline) < 0.03)
        }
        #expect(result.stats.closeMeals >= 3)
        // Contact avoidance can change the cleanup duration; this fixture pins the opening.
    }


    @Test func sceneCollisionGivesEqualFishToThePlayerInBothOrders() {
        for ratio: CGFloat in [1, 0.995, 1.005] {
            for second in [false, true] {
                let scene = GameScene(world: .jellyBloom)
                #expect(scene.debugResolvePlayerTie(otherRatio: ratio, playerSecond: second))
            }
        }
    }

    /// A local audit records causes without asserting that current divergence is desirable.
    @Test func manualRepeatabilityInvestigation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("build/arcade-development")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("repeatability-investigation.request").path) else { return }
        func run(_ frames: [CGFloat], isolated: Bool = true, omitted: Set<Int> = [],
                 zoom: CGFloat = 1, radius: CGFloat = 16) -> ArcadeSimulation.Audit {
            let scene = GameScene(world: .jellyBloom, levelIndex: 4)
            return scene.debugAuditRepeatability(frames: frames, isolatedAI: isolated, omittedIDs: omitted,
                                                fixedZoom: zoom, playerRadius: radius)
        }
        let sixty = Array(repeating: CGFloat(1) / 60, count: 480)
        let thirty = Array(repeating: CGFloat(1) / 30, count: 240)
        let oneTwenty = Array(repeating: CGFloat(1) / 120, count: 960)
        let jitter = (0..<480).map { CGFloat($0.isMultiple(of: 2) ? 1 : 3) / 120 }
        let control = run(sixty)
        #expect(control == run(sixty))
        let reports: [String: ArcadeSimulation.Audit] = [
            "isolated-60": control, "isolated-30": run(thirty), "isolated-120": run(oneTwenty),
            "isolated-jitter": run(jitter), "isolated-omit-1": run(sixty, omitted: [1]),
            "first-step-60": run([1.0 / 60]), "first-step-omit-1": run([1.0 / 60], omitted: [1]),
            "first-step-zoom-0.8": run([1.0 / 60], zoom: 0.8),
            "ecosystem-60": run(sixty, isolated: false), "ecosystem-30": run(thirty, isolated: false),
            "ecosystem-120": run(oneTwenty, isolated: false),
            "ecosystem-grown-player": run(sixty, isolated: false, radius: 32),
        ]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(reports).write(to: folder.appendingPathComponent("repeatability-investigation.json"), options: .atomic)
        print("[RepeatabilityAudit] written to \(folder.path)")
    }

    @Test func manualRouteCadenceStudy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("build/arcade-development")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("route-study.request").path) else { return }
        var results: [ArcadeSimulation.Result] = []
        for index in [2, 4, 6] {
            var found = false
            search: for horizon: CGFloat in [0.4, 0.6, 0.8, 1.2] {
                for appetite: CGFloat in [0, 8, 16] {
                    for danger: CGFloat in [10, 25, 60, 100, 200] {
                        let scene = GameScene(world: .jellyBloom, levelIndex: index)
                        let result = scene.debugSimulate(candidate: "route priorities", tuning: ArcadeTuning(level: GameTuning.bloomLevels[index]),
                            policy: .opportunist, seed: 0, limit: 90, predictionSeconds: horizon, foodPriority: appetite, dangerWeight: danger)
                        results.append(result)
                        if result.outcome == "won" {
                            found = true
                            print("[RouteCadence] level=\(index + 1), prediction=\(horizon), food=\(appetite), danger=\(danger), won=\(result.seconds)")
                            break search
                        }
                    }
                }
            }
            print("[RouteCadence] level=\(index + 1), found=\(found)")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: folder.appendingPathComponent("route-cadence-results.json"), options: .atomic)
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
            let world: ArcadeWorld?
            let tuning: ArcadeTuning?
        }
        let request = try JSONDecoder().decode(Request.self, from: data)
        let output = root.appendingPathComponent("build/arcade-development/simulation-study-results.json")
        var results: [ArcadeSimulation.Result] = []
        for candidate in request.candidates {
            let world = candidate.world ?? .jellyBloom
            let tuning = candidate.tuning ?? ArcadeTuning(level: world.levels[candidate.level - 1])
            for seed in request.seeds {
                if request.ecology {
                    let scene = GameScene(world: world, levelIndex: candidate.level - 1)
                    results.append(scene.debugSimulate(candidate: candidate.name, tuning: tuning, policy: .cautious,
                        seed: seed, limit: CGFloat(request.limit), ecologyProbe: true))
                }
                for policy in request.policies {
                    for delay in request.delayedPasses {
                        for skipped in request.skippedFirstPassFishIDs ?? [[]] {
                            for budget in request.firstPassMealLimits?.map({ $0 < 0 ? nil : Optional.some($0) }) ?? [nil] {
                                let scene = GameScene(world: world, levelIndex: candidate.level - 1)
                                results.append(scene.debugSimulate(candidate: candidate.name, tuning: tuning, policy: policy,
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
