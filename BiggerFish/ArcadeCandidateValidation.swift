#if DEBUG
import CoreGraphics

/// Route evidence, not an estimate of human difficulty or proof that a failed candidate is impossible.
@MainActor
enum ArcadeCandidateValidation {
    struct Report {
        let runs: [ArcadeSimulation.Result]
        let checkedWidths: [Double]
        var missingWidths: [Double] {
            checkedWidths.filter { width in
                !runs.contains { $0.width == width && $0.outcome == "won"
                    && $0.spawned == $0.configured && $0.initialGrowthPath }
            }
        }
        var accepted: Bool { checkedWidths.count == 3 && missingWidths.isEmpty }
    }

    static func check(world: ArcadeWorld, index: Int, tuning: ArcadeTuning) async -> Report? {
        let sizes = [CGSize(width: 874, height: 402), CGSize(width: 852, height: 393), CGSize(width: 667, height: 375)]
        var runs: [ArcadeSimulation.Result] = []
        for size in sizes {
            for policy in ArcadeSimulation.Policy.allCases {
                guard !Task.isCancelled else { return nil }
                // Give the tuning panel time to draw progress and respond to cancellation.
                await Task.yield()
                let scene = GameScene(size: size, world: world, levelIndex: index)
                let result = scene.debugSimulate(candidate: "tuner candidate", tuning: tuning,
                    policy: policy, seed: 0, limit: 90)
                runs.append(result)
                if result.outcome == "won" && result.spawned == result.configured && result.initialGrowthPath { break }
            }
        }
        guard !Task.isCancelled else { return nil }
        return Report(runs: runs, checkedWidths: sizes.map { Double($0.width) })
    }
}
#endif
