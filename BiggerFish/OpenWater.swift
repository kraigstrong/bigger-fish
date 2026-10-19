#if DEBUG
import Foundation

/// The Open Water (Xcode builds only, a prototype for after 1.0): an endless run of stages. Each stage is the first lap
/// of a planned Shallow Reef level, planned as the run reaches it (`MeetingPlanner.kelpPlan`: fish appear just off
/// screen right before you meet them), its settings stepping up `GameTuning.openWaterRamp`. A stage ends when you come
/// round to its start again: you shrink back to your starting size as a bigger fish swims by, and the next stage begins.
/// There's always a bigger fish. Being eaten ends the run.
enum OpenWater {
    /// Stage `stage`'s settings (stages count from 1).
    static func spec(stage: Int) -> MeetingSpec {
        let index = max(0, stage - 1)
        let ramp = GameTuning.openWaterRamp, loop = GameTuning.openWaterLoop
        var spec: MeetingSpec
        if index < ramp.count {
            spec = GameTuning.reefLabSpecs[ramp[index]]
        } else {
            let past = index - ramp.count
            spec = GameTuning.reefLabSpecs[loop[past % loop.count]]
            let faster = 1 + min(GameTuning.openWaterSpeedUpLimit, GameTuning.openWaterSpeedUp * Double(past / loop.count + 1))
            spec.crossSeconds /= faster
            spec.aiSpeed = spec.aiSpeed.lowerBound * faster...spec.aiSpeed.upperBound * faster
        }
        spec.name = "Open Water stage \(stage)"
        return spec
    }

    /// Stage `stage` of the run `seed` names: the same layout every time for the same two. Like Midnight Zone's levels,
    /// the first variation with no planner issues and no wall of giants.
    static func plan(stage: Int, seed: UInt64) -> MeetingPlan {
        let spec = spec(stage: stage), seedName = "Open Water \(seed).\(stage)"
        return (0..<16).lazy.map { MeetingPlanner.kelpPlan(spec, variation: $0, seedName: seedName) }
            .first { $0.issues.isEmpty && !$0.hasGiantWall } ?? MeetingPlanner.kelpPlan(spec, seedName: seedName)
    }
}

/// One Open Water run: its seed, the stage you're on, and the change to the next stage while it plays out.
struct OpenWaterRun {
    let seed: UInt64
    private(set) var stage = 1
    /// The stage change in progress: when it began (game seconds), and your size and the camera's zoom then.
    var change: (start: CGFloat, radius: CGFloat, zoom: CGFloat)?
    /// Stages planned ahead (off the main thread, as the stage before starts).
    private var planned: [Int: MeetingPlan] = [:]

    init(seed: UInt64) {
        self.seed = seed
    }

    /// The stage's plan: planned ahead if it's ready, otherwise now.
    mutating func plan(_ stage: Int) -> MeetingPlan {
        if let plan = planned[stage] { return plan }
        let plan = OpenWater.plan(stage: stage, seed: seed)
        planned[stage] = plan
        return plan
    }

    mutating func store(_ plan: MeetingPlan, stage: Int) {
        if planned[stage] == nil { planned[stage] = plan }
    }

    func hasPlan(_ stage: Int) -> Bool { planned[stage] != nil }

    /// On to the next stage, forgetting the one behind.
    mutating func advance() {
        planned[stage] = nil
        stage += 1
        change = nil
    }
}
#endif
