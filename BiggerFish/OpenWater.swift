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
        // Bells only where the designer puts them: the first level's demo bounce is the searching planner's.
        spec.jellies?.demoBounce = false
        spec.name = "Open Water \(seed).\(index).\(recipe)"
        return spec
    }

    /// The run `seed`'s `index`th level: the same every time for the same two. The first deal that plans with no
    /// issues and no wall of giants, trying many layouts of each (a layout that can't fit is passed over in a moment).
    /// If none does with every open-water big fish the template asks for, and `GameTuning.openWaterFewerToFit` allows,
    /// the same again with one fewer: around bells there's sometimes no room for them all (Jelly Bloom 7's recipe).
    static func plan(_ index: Int, seed: UInt64) -> MeetingPlan {
        var best: MeetingPlan?
        for fewer in 0...(GameTuning.openWaterFewerToFit ? 1 : 0) {
            for recipe in 0..<GameTuning.openWaterDeals {
                var spec = spec(index, seed: seed, recipe: recipe)
                guard spec.extraThreats > fewer else { break }
                spec.extraThreats -= fewer
                for variation in 0..<GameTuning.openWaterLayouts where MeetingPlanner.kelpLayoutFits(spec, variation: variation) {
                    let plan = MeetingPlanner.kelpPlan(spec, variation: variation)
                    if plan.issues.isEmpty && !plan.hasGiantWall && !plan.hasWall { return plan }
                    best = best ?? plan
                }
            }
        }
        return best ?? MeetingPlanner.kelpPlan(spec(index, seed: seed), variation: 0)
    }

    /// The level's pearls (`OpenWaterPearl`): up to `GameTuning.openWaterPearlsPerLevel`, spread along it, each just
    /// beside a big fish's line as you pass it (with `openWaterPearlGap` of water between your body and it on the
    /// reference route), on the side nearer your way and within `openWaterPearlReach` of it, and clear of every other
    /// fish bigger than you, bell, and hook around then. Taking one means brushing past danger; none is ever needed.
    static func pearls(_ plan: MeetingPlan) -> [OpenWaterPearl] {
        typealias T = GameTuning
        let world = WrappedWorld(width: T.playfieldSize.width * CGFloat(plan.spec.worldScreens)), dt = T.simulationStep
        let reference = plan.fish.filter(\.referenceMeal)
        let timeline = plan.referenceTimeline
        // Your way: a straight swim from each reference meal's meeting to the next, from the middle of the water.
        let ids = Set(reference.map(\.id))
        let start = PlayerTimeline.waterBounds(zoom: 1)
        let meals: [(time: CGFloat, y: CGFloat)] = plan.predicted.filter { ids.contains($0.fishID) }.sorted { $0.time < $1.time }
            .map { (time: CGFloat($0.time), y: CGFloat($0.y)) }
        let stops = [(time: CGFloat(0), y: (start.bottom + start.top) / 2)] + meals
        func way(at time: CGFloat) -> CGFloat {
            guard let after = stops.firstIndex(where: { $0.time > time }) else { return stops.last!.y }
            let a = stops[max(0, after - 1)], b = stops[after]
            return a.y + (b.y - a.y) * ((time - a.time) / max(0.01, b.time - a.time)).clamped(0, 1)
        }
        let byID = Dictionary(uniqueKeysWithValues: plan.fish.map { ($0.id, $0) })
        /// Nothing else that could hurt you is near the pearl while you'd be taking it.
        func clear(_ at: CGPoint, step: Int, you: CGFloat, except id: Int) -> Bool {
            for around in stride(from: step - T.openWaterPearlClearSteps, through: step + T.openWaterPearlClearSteps, by: 3) {
                let time = CGFloat(around) * dt
                for f in plan.fish where f.id != id && f.radius > you {
                    guard let p = MeetingSolver.wayInPosition(f, step: around, timeline: timeline) else { continue }
                    if hypot(world.delta(from: p.x, to: at.x), p.y - at.y) < (f.radius + you) * T.collisionScale + T.openWaterPearlGap {
                        return false
                    }
                }
                if let spec = plan.spec.jellies {
                    for jelly in plan.jellies ?? [] {
                        let bell = JellyDrift.position(origin: jelly.origin, phase: jelly.phase, time: time,
                                                       screenWidth: T.playfieldSize.width, world: world)
                        let p = CGPoint(x: world.delta(from: bell.x, to: at.x), y: at.y - bell.y)
                        if MeetingSolver.touchesBell(p, body: you * T.hazardHitboxScale + T.openWaterPearlGap, spec: spec) { return false }
                    }
                }
                for hook in plan.hooks ?? [] {
                    let p = HookMotion.position(hook, time: time)
                    if hypot(world.delta(from: p.x, to: at.x), p.y - at.y) < 1.15 * hook.baitRadius + you + T.openWaterPearlGap {
                        return false
                    }
                }
            }
            return true
        }
        var spots: [CGPoint] = []
        for crossing in plan.predicted.sorted(by: { $0.time < $1.time }) where byID[crossing.fishID]?.role == .threat {
            let step = timeline.step(reaching: CGFloat(crossing.distance))
            let zoom = timeline.zoom[step], you = timeline.radius[step], time = CGFloat(step) * dt
            // A big fish you'd be eaten by, past the level's opening.
            guard time >= T.openWaterPearlEarliest, CGFloat(crossing.radius) > you * (1 + T.nearEqualThreshold) else { continue }
            let offset = (CGFloat(crossing.radius) + you) * T.collisionScale + T.openWaterPearlGap / zoom
            let bounds = PlayerTimeline.waterBounds(zoom: zoom), route = way(at: time), y = CGFloat(crossing.y)
            // The side nearer your way first.
            let sides: [CGFloat] = abs(y + offset - route) <= abs(y - offset - route) ? [1, -1] : [-1, 1]
            for side in sides {
                let at = CGPoint(x: world.wrap(CGFloat(crossing.distance)), y: y + side * offset)
                guard (bounds.bottom + you...bounds.top - you).contains(at.y), abs(at.y - route) <= T.openWaterPearlReach / zoom,
                      clear(at, step: step, you: you, except: crossing.fishID) else { continue }
                spots.append(at)
                break
            }
        }
        // Spread along the level: every so many of the spots, as many as a level has.
        let count = min(spots.count, T.openWaterPearlsPerLevel)
        guard count > 0 else { return [] }
        return (0..<count).map { k in
            let at = spots[spots.count > 1 ? (k * (spots.count - 1)) / max(1, count - 1) : 0]
            return OpenWaterPearl(position: at, phase: CGFloat(k) * 1.9)
        }
    }

    /// The level's last gate: eating it ends the level.
    static func finale(_ plan: MeetingPlan) -> Int? {
        plan.fish.filter { $0.role == .gate }.max { $0.meetingDistance < $1.meetingDistance }?.id
    }
}

/// A pearl in an Open Water level: where it sits in the water (world point), and when it bobs. Touch it to take it:
/// it doesn't grow you, other fish leave it alone, and no gate needs it.
struct OpenWaterPearl: Equatable {
    let position: CGPoint
    let phase: CGFloat
}

/// One Open Water run: its seed, the level you're on, and the levels planned ahead.
struct OpenWaterRun {
    let seed: UInt64
    /// Which of the run's levels you're on (from 0; `OpenWater.leg`).
    private(set) var index = 0
    var leg: OpenWater.Leg { OpenWater.leg(index) }
    /// You've eaten this level's last gate.
    var finished = false
    /// Pearls taken this run.
    var pearls = 0
    /// Levels planned ahead (off the main thread, as the one before starts).
    private var planned: [Int: MeetingPlan] = [:]

    /// `index`: start further on (playtesting a world: `-openWaterLevel`).
    init(seed: UInt64, index: Int = 0) {
        self.seed = seed
        self.index = index
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
    }
}
#endif
