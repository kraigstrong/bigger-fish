#if DEBUG
import FishKit
import Foundation

/// The Open Water (Xcode builds only, a prototype for after 1.0): an endless run round the campaign's worlds. A stage
/// is one time round: each world in turn (`GameTuning.openWaterWorlds`) plays a new level made at its own level's
/// difficulty, level 5 on stage 1, 6 on stage 2, and on (`GameTuning.openWaterFirstLevel`). Each is planned as the run
/// reaches it. A level ends on its last gate: eat it and you shrink back to your starting size for the next world.
/// There's always a bigger fish. Being eaten ends the run.
enum OpenWater {
    /// One level of a run: its stage, its world, and which of that world's levels it's made like (from 1; past the
    /// Deep End's last, 15, it goes on as 16, 17, and on).
    struct Leg: Equatable {
        let stage: Int
        let world: ArcadeWorld
        let level: Int
    }

    /// The run's `index`th level (from 0).
    static func leg(_ index: Int) -> Leg {
        let worlds = GameTuning.openWaterWorlds
        let stage = index / worlds.count + 1
        return Leg(stage: stage, world: worlds[index % worlds.count], level: GameTuning.openWaterFirstLevel + stage - 1)
    }

    /// The settings `world`'s own level `level` was made with: its speeds, sizes, margins, and the world's hazards
    /// (jellies, kelp, hooks). Past the Deep End's last level, its five again and again, each time round a little
    /// faster (your swim and the fish's).
    static func template(_ world: ArcadeWorld, level: Int) -> MeetingSpec {
        let deepEnd = ArcadeWorld.mainLevelCount, last = deepEnd + 5
        let past = max(0, level - last - 1)
        let slot = level <= last ? max(0, level - 1) : deepEnd + past % 5
        var spec: MeetingSpec
        switch world {
        case .shallowReef: spec = GameTuning.reefLabSpecs[GameTuning.shallowReefOrder[slot]]
        case .jellyBloom: spec = GameTuning.jellyLabSpecs[slot]
        case .kelpForest: spec = GameTuning.kelpSpecs[slot]
        case .sunsetCove: spec = GameTuning.sunsetSpecs[slot]
        case .midnightZone: spec = GameTuning.midnightSpecs[slot]
        case .riptideReef: spec = GameTuning.riptideSpecs[min(slot, GameTuning.riptideSpecs.count - 1)]
        }
        if level > last {
            let faster = 1 + min(GameTuning.openWaterSpeedUpLimit, GameTuning.openWaterSpeedUp * Double(past / 5 + 1))
            spec.crossSeconds /= faster
            spec.aiSpeed = spec.aiSpeed.lowerBound * faster...spec.aiSpeed.upperBound * faster
        }
        return spec
    }

    /// A new level made like the leg's template, so it plays at that difficulty without being a copy: each segment's
    /// singles and long lanes re-dealt a meal either way, its gate needing as many meals as the short lanes bring less
    /// the template's slack, and its dangers kept. `recipe` deals again when a deal doesn't plan.
    static func spec(_ index: Int, seed: UInt64, recipe: Int = 0) -> MeetingSpec {
        var spec = template(leg(index).world, level: leg(index).level)
        var rng = SeededGenerator(seed: seed &* 0x9E37_79B9 &+ UInt64(index) &* 1_000_003 &+ UInt64(recipe) &* 7_919)
        spec.segments = spec.segments.map { base in
            var segment = base
            segment.singles = (base.singles + Int.random(in: -1...1, using: &rng)).clamped(0, 3)
            segment.forks = base.forks.map { fork in
                var fork = fork
                // A lane split by a jelly starts on its dome and climbs with the bounce: it needs two meals.
                fork.long = (fork.long + Int.random(in: -1...1, using: &rng)).clamped(max(fork.short, fork.splitsOnAJelly ? 2 : 1), 3)
                return fork
            }
            let slack = max(0, base.singles + base.forks.reduce(0) { $0 + $1.short } - base.needed)
            let short = segment.singles + segment.forks.reduce(0) { $0 + $1.short }
            segment.needed = min(segment.mostMeals, max(1, short - slack))
            segment.dangerFoods = min(base.dangerFoods, segment.mostMeals)
            return segment
        }
        spec.name = "Open Water \(seed).\(index).\(recipe)"
        return spec
    }

    /// The run `seed`'s `index`th level: the same every time for the same two. The first deal that plans with no
    /// issues and no wall of giants, trying a few layouts of each.
    static func plan(_ index: Int, seed: UInt64) -> MeetingPlan {
        var best: MeetingPlan?
        for recipe in 0..<GameTuning.openWaterDeals {
            let spec = spec(index, seed: seed, recipe: recipe)
            let plans: [MeetingPlan] = spec.jellies == nil
                ? (0..<4).map { MeetingPlanner.kelpPlan(spec, variation: $0) } : [MeetingPlanner.plan(spec)]
            if let clean = plans.first(where: { $0.issues.isEmpty && !$0.hasGiantWall }) { return clean }
            best = best ?? plans.first
        }
        return best!
    }

    /// The level's last gate: eating it ends the level.
    static func finale(_ plan: MeetingPlan) -> Int? {
        plan.fish.filter { $0.role == .gate }.max { $0.meetingDistance < $1.meetingDistance }?.id
    }
}

/// One Open Water run: its seed, the level you're on, and the change to the next while it plays out.
struct OpenWaterRun {
    let seed: UInt64
    /// Which of the run's levels you're on (from 0; `OpenWater.leg`).
    private(set) var index = 0
    var leg: OpenWater.Leg { OpenWater.leg(index) }
    /// You've eaten this level's last gate.
    var finished = false
    /// Pearls picked up this run (none are placed yet).
    var pearls = 0
    /// The change to the next level in progress: when it began (game seconds), and your size and the camera's zoom then.
    var change: (start: CGFloat, radius: CGFloat, zoom: CGFloat)?
    /// Levels planned ahead (off the main thread, as the one before starts).
    private var planned: [Int: MeetingPlan] = [:]

    init(seed: UInt64) {
        self.seed = seed
    }

    /// A level's plan: planned ahead if it's ready, otherwise now.
    mutating func plan(_ index: Int) -> MeetingPlan {
        if let plan = planned[index] { return plan }
        let plan = OpenWater.plan(index, seed: seed)
        planned[index] = plan
        return plan
    }

    mutating func store(_ plan: MeetingPlan, index: Int) {
        if planned[index] == nil { planned[index] = plan }
    }

    func hasPlan(_ index: Int) -> Bool { planned[index] != nil }

    /// On to the next level, forgetting the one behind.
    mutating func advance() {
        planned[index] = nil
        index += 1
        finished = false
        change = nil
    }
}
#endif
