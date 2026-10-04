#if DEBUG
import CoreGraphics

/// Route evidence, not an estimate of human difficulty or proof that a failed candidate is impossible.
@MainActor
enum ArcadeCandidateValidation {
    struct Report {
        let runs: [ArcadeSimulation.Result]
        var accepted: Bool {
            runs.contains { $0.outcome == "won" && $0.spawned == $0.configured && $0.initialGrowthPath }
        }
    }

    static func check(world: ArcadeWorld, index: Int, tuning: ArcadeTuning) async -> Report? {
        var runs: [ArcadeSimulation.Result] = []
        for policy in ArcadeSimulation.Policy.allCases {
            guard !Task.isCancelled else { return nil }
            // Give the tuning panel time to draw progress and respond to cancellation.
            await Task.yield()
            let scene = GameScene(world: world, levelIndex: index)
            let result = scene.debugSimulate(candidate: "tuner candidate", tuning: tuning,
                policy: policy, seed: 0, limit: 90)
            runs.append(result)
            if result.outcome == "won" && result.spawned == result.configured && result.initialGrowthPath { break }
        }
        guard !Task.isCancelled else { return nil }
        return Report(runs: runs)
    }
}
#endif
