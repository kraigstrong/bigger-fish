import CoreGraphics
import FishKit
import SpriteKit

// Sunset Cove's fish hooks: boats at the surface each lower a line to a baited hook. The bait is a little fish on the
// hook, and it looks like a meal: bite it, or touch the hook, and you're reeled up out of the water. The line is
// harmless, and other fish ignore hooks entirely (Kraig: "I don't think other fish should take the bait").

/// A level's hooks: how many of each kind, where they hang, and their bait.
struct HookSpec: Codable, Equatable {
    /// Hooks that hang still, hooks reeled slowly up and down, and hooks trolled along by a drifting boat.
    var still = 0
    var bobbing = 0
    var trolling = 0
    /// Two still hooks near the end of the lap, one above your way and one below, narrowing the gap between them.
    var gate = false
    /// Hooks hung beside a real meal, with bait that meal's size (still or bobbing hooks first). One that finds no meal
    /// with a fair spot beside it hangs near a lane instead.
    var besideMeals = 0
    /// Hooks hung as near your way as the clearance allows, so you pick a lane; the rest hang well clear of it.
    var nearLanes = 0
    /// Bait radius as a share of yours when you pass it (bait beside a meal is that meal's size).
    var baitSize: Double = 0.6
    /// Screen points of water kept between a hook (bait and all) and your way from meal to meal, beyond your body.
    var clearance: Double = 40

    var count: Int { still + bobbing + trolling + (gate ? 2 : 0) }
}

/// A hook the planner hung: where it is at any time (`HookMotion`), its bait, and when the reference route passes it.
struct PlannedHook: Codable, Equatable {
    enum Motion: String, Codable { case still, bob, troll }
    /// Why it hangs where it does: well off your way, near a lane, beside a meal, or one side of the gate.
    enum Role: String, Codable { case open, lane, beside, gate }
    let motion: Motion
    let role: Role
    /// World x of the hook at the start (a trolling hook moves on from here).
    let x: CGFloat
    /// World y of the hook: where a still hook hangs, a bobbing hook's lowest, the middle of a trolling hook's sweep.
    let depth: CGFloat
    /// World points a bobbing hook is reeled up, or a trolling hook sweeps either way.
    let range: CGFloat
    /// Seconds for one bob, or one sweep there and back.
    let period: CGFloat
    let phase: CGFloat
    /// World points a second a trolling hook's boat moves: negative, as it motors toward you.
    let speed: CGFloat
    let baitRadius: CGFloat
    /// Seconds into the run that the reference route passes it.
    let passTime: CGFloat
    /// The bait's look and its boat's.
    var styleSeed: UInt64
}

/// Where a hook is: a pure function of time, so the planner, the scene, and the bots all agree.
enum HookMotion {
    /// The hook (the bait's center), with x unwrapped.
    static func position(_ hook: PlannedHook, time: CGFloat) -> CGPoint {
        switch hook.motion {
        case .still:
            CGPoint(x: hook.x, y: hook.depth)
        case .bob:
            CGPoint(x: hook.x, y: hook.depth + hook.range * (0.5 - 0.5 * cos(2 * .pi * time / hook.period + hook.phase)))
        case .troll:
            CGPoint(x: hook.x + hook.speed * time, y: hook.depth + hook.range * sin(2 * .pi * time / hook.period + hook.phase))
        }
    }

    /// Where its line leaves the boat's rod, world x (unwrapped): straight above the hook, or ahead of it (toward you)
    /// for a boat trolling it along behind.
    static func rodX(_ hook: PlannedHook, time: CGFloat) -> CGFloat {
        position(hook, time: time).x - (hook.motion == .troll ? GameTuning.sunsetTrollTrail : 0)
    }
}

/// What a hook catches. Coordinates are relative to the bait's center; the hook's bend hangs under its belly.
enum HookRules {
    /// The hook's bend, as a share of the bait's radius.
    static let bend = CGPoint(x: 0.3, y: -0.8)

    /// Whether a fish of `radius` at `point` touches the bait or the hook (never the line).
    static func catches(_ point: CGPoint, radius: CGFloat, hook: CGPoint, bait: CGFloat, world: WrappedWorld) -> Bool {
        let body = radius * GameTuning.hazardHitboxScale
        let dx = world.delta(from: hook.x, to: point.x), dy = point.y - hook.y
        if hypot(dx, dy) < body + bait * GameTuning.sunsetBaitHitScale { return true }
        return hypot(dx - bend.x * bait, dy - bend.y * bait) < body + bait * GameTuning.sunsetHookHitShare
    }

    /// How far the deadly part reaches below and above the hook's center (world points), for keeping it off your way.
    static func reach(bait: CGFloat) -> (below: CGFloat, above: CGFloat, across: CGFloat) {
        (bait * (-bend.y + GameTuning.sunsetHookHitShare), bait * GameTuning.sunsetBaitHitScale,
         bait * max(GameTuning.sunsetBaitHitScale, bend.x + GameTuning.sunsetHookHitShare))
    }
}

// MARK: - Art

/// A boat seen from under the water: a dark hull at the surface, its rod over the stern. Drawn at the reference scale
/// (zoom 1) with its origin where the line leaves the rod, at the waterline; the hull runs ahead of it, to the left,
/// pointing the way it goes across the screen as you swim past (Kraig: a boat facing the way you swim looked like it
/// was backing up).
final class HookBoatNode: SKNode {
    init(seed: UInt64) {
        super.init()
        // Drawn bow to the right, then turned round.
        let art = SKNode()
        art.xScale = -1
        addChild(art)
        var rng = SeededGenerator(seed: seed)
        let length = GameTuning.sunsetBoatLength * CGFloat.random(in: 0.9...1.1, using: &rng)
        let draft = GameTuning.sunsetBoatDraft
        let stern: CGFloat = 8, bow = stern + length
        // The hull from below: a flat transom at the stern, a rounded bottom, and a bow that rakes up and ahead.
        let hull = CGMutablePath()
        hull.move(to: CGPoint(x: stern, y: 8))
        hull.addLine(to: CGPoint(x: bow + 14, y: 8))
        hull.addQuadCurve(to: CGPoint(x: bow - 18, y: -draft * 0.8), control: CGPoint(x: bow + 2, y: -draft * 0.55))
        hull.addQuadCurve(to: CGPoint(x: stern + 10, y: -draft * 0.85), control: CGPoint(x: (stern + bow) / 2, y: -draft * 1.15))
        hull.addLine(to: CGPoint(x: stern, y: -draft * 0.6))
        hull.closeSubpath()
        let body = SKShapeNode(path: hull)
        body.fillColor = GameTuning.sunsetBoatColor
        // The low sun catches its edge.
        body.strokeColor = SKColor(red: 1, green: 0.7, blue: 0.5, alpha: 0.7)
        body.lineWidth = 1.5
        // Over the cabin and the outboard (they're the hull's color, but it has a rim): the scene ignores sibling order.
        body.zPosition = 0
        art.addChild(body)
        // A cabin above the deck, and the outboard under the stern: its leg and propeller.
        let cabin = SKShapeNode(rect: CGRect(x: stern + length * 0.4, y: 6, width: length * 0.32, height: 16), cornerRadius: 3)
        cabin.fillColor = GameTuning.sunsetBoatColor
        cabin.strokeColor = .clear
        cabin.zPosition = -0.05
        art.addChild(cabin)
        let motor = CGMutablePath()
        motor.addRoundedRect(in: CGRect(x: stern - 6, y: -draft * 0.3, width: 12, height: draft * 0.5), cornerWidth: 3, cornerHeight: 3)
        // Apart from one another, so they fill alike whatever the fill rule.
        motor.addRect(CGRect(x: stern - 2, y: -draft * 1.05, width: 4, height: draft * 0.75))
        motor.addEllipse(in: CGRect(x: stern - 5, y: -draft * 1.05 - 6, width: 10, height: 6))
        let outboard = SKShapeNode(path: motor)
        outboard.fillColor = GameTuning.sunsetBoatColor
        outboard.strokeColor = .clear
        outboard.zPosition = -0.05
        art.addChild(outboard)
        // The rod, out over the stern to where the line leaves it.
        let rodPath = CGMutablePath()
        rodPath.move(to: CGPoint(x: stern + 14, y: 7))
        rodPath.addQuadCurve(to: CGPoint(x: 0, y: 4), control: CGPoint(x: stern * 0.5, y: 14))
        let rod = SKShapeNode(path: rodPath)
        rod.strokeColor = GameTuning.sunsetBoatColor
        rod.lineWidth = 2.5
        rod.lineCap = .round
        rod.zPosition = 0.05
        art.addChild(rod)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The hook itself at a bait radius of `FishNode.referenceRadius`: an eye over the bait for the line, a shank down
/// behind it, the bend under its belly, and a barbed point. Scale it by the bait's radius over the reference.
enum HookMetal {
    /// Where the line ties on, as a share of the bait's radius above its center.
    static let eye: CGFloat = 1.25

    static func make() -> SKShapeNode {
        let b = FishNode.referenceRadius
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -0.1 * b, y: (eye - 0.1) * b, width: 0.2 * b, height: 0.2 * b))
        path.move(to: CGPoint(x: 0, y: (eye - 0.1) * b))
        path.addLine(to: CGPoint(x: 0, y: -0.8 * b))
        path.addArc(center: CGPoint(x: 0.3 * b, y: -0.8 * b), radius: 0.3 * b, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: 0.6 * b, y: -0.4 * b))
        path.addLine(to: CGPoint(x: 0.47 * b, y: -0.52 * b))
        let node = SKShapeNode(path: path)
        // Dark steel, so it shows against the pink water and the bait.
        node.strokeColor = SKColor(red: 0.22, green: 0.18, blue: 0.28, alpha: 1)
        node.fillColor = .clear
        node.lineWidth = 2.6
        node.lineCap = .round
        node.lineJoin = .round
        return node
    }
}

/// A splash where something leaves the water: droplets thrown up and a ring at the surface.
enum HookSplash {
    static func make(width: CGFloat) -> SKNode {
        let splash = SKNode()
        var rng = SeededGenerator(seed: 41)
        for index in 0..<7 {
            let drop = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.6...3, using: &rng))
            drop.fillColor = SKColor(red: 1, green: 0.92, blue: 0.85, alpha: 0.9)
            drop.strokeColor = .clear
            let spread = (CGFloat(index) - 3) / 3
            let rise = CGFloat.random(in: 18...34, using: &rng)
            drop.run(.sequence([
                .group([.moveBy(x: spread * width * 0.9, y: rise, duration: 0.22), .fadeAlpha(to: 0.8, duration: 0.22)]),
                .group([.moveBy(x: spread * width * 0.4, y: -rise * 0.8, duration: 0.25), .fadeOut(withDuration: 0.25)]),
                .removeFromParent(),
            ]))
            splash.addChild(drop)
        }
        let ring = SKShapeNode(ellipseOf: CGSize(width: width, height: width * 0.25))
        ring.strokeColor = SKColor(red: 1, green: 0.92, blue: 0.85, alpha: 0.8)
        ring.fillColor = .clear
        ring.lineWidth = 1.5
        ring.run(.sequence([.group([.scaleX(to: 2.4, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        splash.addChild(ring)
        splash.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))
        return splash
    }
}

// MARK: - Planning

// The planner runs in Xcode builds and tests only, like the meeting planner.
#if DEBUG
/// Hangs a level's hooks around its planned meetings. The reference route the meetings were timed against must stay
/// open: every hook keeps clear of your way from meal to meal (and of every reference meal's meeting) by a margin,
/// for a little before and after you pass it, so a hook makes you pick a lane rather than forcing a death.
enum HookLayout {
    typealias T = GameTuning

    /// The reference route: the meals the meetings were timed against, and your size, zoom, and distance at every step.
    struct Route {
        struct Stop { let time: CGFloat; let y: CGFloat; let radius: CGFloat; let distance: CGFloat }
        /// Where you start, then each reference meal's meeting, in order.
        let stops: [Stop]
        let timeline: PlayerTimeline

        init(fish: [PlannedFish], crossings: [EncounterCrossing], timeline: PlayerTimeline) {
            let reference = Set(fish.filter(\.referenceMeal).map(\.id))
            let start = Stop(time: 0, y: (PlayerTimeline.waterBounds(zoom: 1).bottom + PlayerTimeline.waterBounds(zoom: 1).top) / 2,
                             radius: 0, distance: 0)
            stops = [start] + crossings.filter { reference.contains($0.fishID) }.sorted { $0.time < $1.time }
                .map { Stop(time: CGFloat($0.time), y: CGFloat($0.y), radius: CGFloat($0.radius), distance: CGFloat($0.distance)) }
            self.timeline = timeline
        }

        var meals: ArraySlice<Stop> { stops.dropFirst() }
        func step(_ time: CGFloat) -> Int { min(timeline.lastStep, max(0, Int((time / T.simulationStep).rounded()))) }
        func distance(_ time: CGFloat) -> CGFloat { timeline.distance[step(time)] }
        func radius(_ time: CGFloat) -> CGFloat { timeline.radius[step(time)] }
        func zoom(_ time: CGFloat) -> CGFloat { timeline.zoom[step(time)] }
        /// The heights your way can be at at `time`, between the last meal (or the start) and the next: no farther from
        /// the last than you could have swum since, and no farther from the next than you could still swim in time. Every
        /// way of eating both stays inside.
        func band(_ time: CGFloat) -> ClosedRange<CGFloat> {
            guard let next = stops.firstIndex(where: { $0.time > time }) else { return stops.last!.y...stops.last!.y }
            let a = stops[max(0, next - 1)], b = stops[next]
            let speed = T.motion.maxRiseSpeed / zoom(time), delta = b.y - a.y, way: CGFloat = delta < 0 ? -1 : 1
            let eager = a.y + way * min(abs(delta), speed * max(0, time - a.time))
            let late = b.y - way * min(abs(delta), speed * max(0, b.time - time))
            return min(eager, late)...max(eager, late)
        }
    }

    /// Passing a hook: from when you're level with it (your body within reach of its bait, plus the clearance) to when
    /// you're past, widened by `window` either side; and the heights your way and your body span over that time.
    struct Pass {
        let from: CGFloat
        let to: CGFloat
        let low: CGFloat
        let high: CGFloat
    }

    /// When you pass a hook and where your way runs meanwhile. It depends on how the hook moves along and its bait,
    /// not its depth, so one pass serves every depth tried at the same moment.
    static func pass(_ hook: PlannedHook, route: Route, clearance: CGFloat, window: CGFloat = T.sunsetPassWindow) -> Pass? {
        let across = HookRules.reach(bait: hook.baitRadius).across
        let dt = T.simulationStep
        var first: CGFloat?, last: CGFloat?
        var time = max(0, hook.passTime - 1)
        while time <= hook.passTime + 1 {
            let dx = route.distance(time) - HookMotion.position(hook, time: time).x
            if abs(dx) < route.radius(time) * T.hazardHitboxScale + across + clearance / route.zoom(time) {
                if first == nil { first = time }
                last = time
            }
            time += dt
        }
        guard let first, let last else { return nil }
        var low = CGFloat.infinity, high = -CGFloat.infinity
        time = max(0, first - window)
        while time <= last + window {
            let band = route.band(time)
            let body = route.radius(time) * T.hazardHitboxScale + clearance / route.zoom(time)
            low = min(low, band.lowerBound - body)
            high = max(high, band.upperBound + body)
            time += dt
        }
        return Pass(from: max(0, first - window), to: last + window, low: low, high: high)
    }

    /// The narrowest water between a hook's deadly part and your way while you pass it (negative: it's in your way).
    static func gap(_ hook: PlannedHook, pass: Pass) -> CGFloat {
        let reach = HookRules.reach(bait: hook.baitRadius)
        var low = CGFloat.infinity, high = -CGFloat.infinity
        if hook.motion == .still {
            (low, high) = (hook.depth - reach.below, hook.depth + reach.above)
        } else {
            var time = pass.from
            while time <= pass.to + 0.001 {
                let y = HookMotion.position(hook, time: time).y
                low = min(low, y - reach.below)
                high = max(high, y + reach.above)
                time += T.simulationStep * 2
            }
        }
        return max(low - pass.high, pass.low - high)
    }

    /// How a hook sits against your way while you pass it, `window` seconds either side (see `gap(_:pass:)`).
    static func gap(_ hook: PlannedHook, route: Route, clearance: CGFloat, window: CGFloat = T.sunsetPassWindow) -> CGFloat {
        guard let pass = pass(hook, route: route, clearance: clearance, window: window) else { return .infinity }
        return gap(hook, pass: pass)
    }

    /// Whether a hook keeps clear of a reference meal's meeting: far enough along, or far enough above or below, when
    /// you meet that meal. Margins are screen points beyond both bodies.
    static func clears(_ hook: PlannedHook, meal: Route.Stop, zoom: CGFloat) -> Bool {
        let at = HookMotion.position(hook, time: meal.time)
        let bodies = meal.radius + HookRules.reach(bait: hook.baitRadius).across
        return abs(meal.distance - at.x) >= bodies + T.sunsetMealClearance.distance / zoom
            || abs(meal.y - at.y) >= bodies + T.sunsetMealClearance.height / zoom
    }

    /// Whether every part of a hook's swing stays in the water, under its boat and above the floor, as the camera sees
    /// it at `zoom` (you, as big as you are when you pass it; bigger, the camera sees more water).
    static func fits(_ hook: PlannedHook, zoom: CGFloat) -> Bool {
        let water = PlayerTimeline.waterBounds(zoom: zoom)
        let reach = HookRules.reach(bait: hook.baitRadius)
        let (low, high): (CGFloat, CGFloat) = switch hook.motion {
        case .still: (hook.depth, hook.depth)
        case .bob: (hook.depth, hook.depth + hook.range)
        case .troll: (hook.depth - hook.range, hook.depth + hook.range)
        }
        return low - reach.below >= water.bottom + T.sunsetFloorRoom / zoom
            && high + hook.baitRadius * HookMetal.eye <= water.top - (T.sunsetBoatDraft + T.sunsetSurfaceRoom) / zoom
    }

    /// The level's hooks, hung around its planned meetings, and any it couldn't fit.
    static func place(_ spec: HookSpec, fish: [PlannedFish], crossings: [EncounterCrossing],
                      timeline: PlayerTimeline, seed: UInt64) -> (hooks: [PlannedHook], issues: [String]) {
        var rng = SeededGenerator(seed: seed &+ 0x486F_6F6B)
        let route = Route(fish: fish, crossings: crossings, timeline: timeline)
        guard let lastMeal = route.meals.last else { return ([], ["no reference route to hang hooks around"]) }
        let width = T.playfieldSize.width
        let firstTime = CGFloat(timeline.step(reaching: width * T.sunsetFirstHookScreens)) * T.simulationStep
        let lastTime = lastMeal.time - T.sunsetHookSpacing / 2
        let clearance = CGFloat(spec.clearance)
        let foods = crossings.filter { crossing in fish.first { $0.id == crossing.fishID }?.role == .food }
        var placed: [PlannedHook] = []
        var issues: [String] = []

        /// A hook of this kind that you pass at `passTime` with it at height `y`.
        func hook(_ motion: PlannedHook.Motion, role: PlannedHook.Role, passTime: CGFloat, y: CGFloat, bait: CGFloat,
                  phase: CGFloat) -> PlannedHook {
            let zoom = route.zoom(passTime), x = route.distance(passTime)
            switch motion {
            case .still:
                return PlannedHook(motion: .still, role: role, x: x, depth: y, range: 0, period: 1, phase: 0, speed: 0,
                                   baitRadius: bait, passTime: passTime, styleSeed: 0)
            case .bob:
                // Passed at the end of its bob that's away from your way: at the top over it, at the bottom under it.
                let range = T.sunsetBobRange / zoom, omega = 2 * .pi / T.sunsetBobSeconds
                let above = y > route.band(passTime).upperBound
                return PlannedHook(motion: .bob, role: role, x: x, depth: above ? y - range : y, range: range,
                                   period: T.sunsetBobSeconds, phase: (above ? .pi : 0) - omega * passTime, speed: 0,
                                   baitRadius: bait, passTime: passTime, styleSeed: 0)
            case .troll:
                let range = T.sunsetTrollSweep / zoom, speed = -T.sunsetTrollSpeed / zoom
                let angle = 2 * .pi * passTime / T.sunsetTrollSweepSeconds + phase
                return PlannedHook(motion: .troll, role: role, x: x - speed * passTime, depth: y - range * sin(angle),
                                   range: range, period: T.sunsetTrollSweepSeconds, phase: phase, speed: speed,
                                   baitRadius: bait, passTime: passTime, styleSeed: 0)
            }
        }

        /// A hook is fair if it fits the water, keeps its distance from the other hooks and every reference meal's
        /// meeting, and keeps clear of your way as you pass it. Returns how far clear.
        /// Why candidates were turned down, for a hook that finds no room.
        var rejected: [String: Int] = [:]
        func fair(_ candidate: PlannedHook, pass known: Pass? = nil) -> CGFloat? {
            guard fits(candidate, zoom: route.zoom(candidate.passTime)) else { rejected["water", default: 0] += 1; return nil }
            guard placed.allSatisfy({ abs($0.passTime - candidate.passTime) >= T.sunsetHookSpacing }) else {
                rejected["spacing", default: 0] += 1; return nil
            }
            guard route.meals.allSatisfy({ clears(candidate, meal: $0, zoom: route.zoom($0.time)) }) else {
                rejected["meal", default: 0] += 1; return nil
            }
            guard let pass = known ?? Self.pass(candidate, route: route, clearance: clearance) else { return nil }
            let gap = Self.gap(candidate, pass: pass)
            if gap < 0 { rejected["way", default: 0] += 1 }
            return gap >= 0 ? gap : nil
        }
        func why() -> String {
            defer { rejected.removeAll() }
            return rejected.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        }
        func keep(_ hook: PlannedHook) {
            var hook = hook
            hook.styleSeed = rng.next()
            placed.append(hook)
        }

        /// Clear of every fish crossing nearby, so its bait reads as its own fish (bait beside a meal sits beside it).
        func apart(_ candidate: PlannedHook) -> Bool {
            crossings.allSatisfy { crossing in
                let time = CGFloat(crossing.time)
                guard abs(time - candidate.passTime) < 0.15 else { return true }
                let at = HookMotion.position(candidate, time: time)
                return abs(CGFloat(crossing.y) - at.y) >= CGFloat(crossing.radius) + candidate.baitRadius + 4
            }
        }

        func baitRadius(at time: CGFloat) -> CGFloat {
            max(T.sunsetSmallestBait, route.radius(time) * CGFloat(spec.baitSize))
        }

        // The gate first: two still hooks near the end, either side of your way where it's narrowest.
        if spec.gate {
            let mealTimes = route.meals.map(\.time)
            let earliest = max(firstTime, mealTimes[min(mealTimes.count - 1, Int(CGFloat(mealTimes.count) * T.sunsetGateFrom))])
            var best: (score: CGFloat, hooks: [PlannedHook])?
            var time = earliest
            while time <= lastTime {
                // Each side hung just clear of your way as you pass it: the upper hook over it, then the lower under it.
                let lowerTime = time + T.sunsetGateStagger
                let bait = baitRadius(at: time), lowerBait = baitRadius(at: lowerTime)
                if let over = Self.pass(hook(.still, role: .gate, passTime: time, y: 0, bait: bait, phase: 0),
                                        route: route, clearance: clearance, window: T.sunsetGateWindow),
                   let under = Self.pass(hook(.still, role: .gate, passTime: lowerTime, y: 0, bait: lowerBait, phase: 0),
                                         route: route, clearance: clearance, window: T.sunsetGateWindow) {
                    // As close as fair: a little farther off if a meal you meet then is too near.
                    let upper = stride(from: CGFloat(1), through: 41, by: 8).lazy.map { extra in
                        hook(.still, role: .gate, passTime: time, y: over.high + HookRules.reach(bait: bait).below + extra,
                             bait: bait, phase: 0)
                    }.first { fair($0, pass: over) != nil }
                    let lower = stride(from: CGFloat(1), through: 41, by: 8).lazy.map { extra in
                        hook(.still, role: .gate, passTime: lowerTime, y: under.low - HookRules.reach(bait: lowerBait).above - extra,
                             bait: lowerBait, phase: 0)
                    }.first { fair($0, pass: under) != nil }
                    if let upper, let lower {
                        // The narrowest gap, late in the lap.
                        let gap = (upper.depth - HookRules.reach(bait: bait).below) - (lower.depth + HookRules.reach(bait: lowerBait).above)
                        let score = -gap * route.zoom(time) + (time - earliest) * 10
                        if best.map({ score > $0.score }) ?? true { best = (score, [upper, lower]) }
                    }
                }
                time += 0.05
            }
            if let best {
                best.hooks.forEach(keep)
            } else {
                issues.append("no room for the hook gate (\(why()))")
            }
        }

        // The rest, one to each stretch of the lap (the gate keeps its own moment), in a shuffled order of kinds.
        var kinds = Array(repeating: PlannedHook.Motion.still, count: spec.still)
            + Array(repeating: .bob, count: spec.bobbing) + Array(repeating: .troll, count: spec.trolling)
        kinds.shuffle(using: &rng)
        var roles = Array(repeating: PlannedHook.Role.open, count: kinds.count)
        var besides = spec.besideMeals, lanes = spec.nearLanes
        for index in kinds.indices where kinds[index] != .troll && besides > 0 { roles[index] = .beside; besides -= 1 }
        for index in kinds.indices where roles[index] == .open && lanes > 0 { roles[index] = .lane; lanes -= 1 }
        let end = lastTime
        let stretch = (end - firstTime) / CGFloat(max(1, kinds.count))
        for (index, kind) in kinds.enumerated() {
            rejected.removeAll()
            // Its own stretch of the lap, or failing that, as near it as there's room.
            let center = firstTime + stretch * (CGFloat(index) + 0.5)
            let from = firstTime, to = end
            func away(_ time: CGFloat) -> CGFloat { max(0, abs(time - center) - stretch / 2) * T.sunsetStretchPull }
            let phase = CGFloat.random(in: 0..<(2 * .pi), using: &rng)
            var best: (score: CGFloat, hook: PlannedHook)?
            func consider(_ candidate: PlannedHook, pass: Pass? = nil, score: (CGFloat) -> CGFloat) {
                guard let gap = fair(candidate, pass: pass) else { return }
                let value = score(gap) - away(candidate.passTime)
                if best.map({ value > $0.score }) ?? true { best = (value, candidate) }
            }
            if roles[index] == .beside {
                // Beside a meal you meet near its stretch, its bait the meal's size.
                for food in foods where (from...to).contains(CGFloat(food.time)) {
                    let time = CGFloat(food.time), bait = max(T.sunsetSmallestBait, CGFloat(food.radius))
                    let reach = HookRules.reach(bait: bait), zoom = route.zoom(time)
                    let offset = CGFloat(food.radius) + T.sunsetBesideGap / zoom
                    for y in [CGFloat(food.y) + offset + reach.below, CGFloat(food.y) - offset - reach.above] {
                        consider(hook(kind, role: .beside, passTime: time, y: y, bait: bait, phase: phase)) { gap in -gap * 0.1 }
                    }
                }
            }
            if best == nil {
                let role: PlannedHook.Role = roles[index] == .beside ? .lane : roles[index]
                var time = from
                while time <= to {
                    // The water as you see it when you pass.
                    let water = PlayerTimeline.waterBounds(zoom: route.zoom(time)), bait = baitRadius(at: time)
                    // When you pass it doesn't depend on its height: one pass for every height tried.
                    let probe = hook(kind, role: role, passTime: time, y: (water.bottom + water.top) / 2, bait: bait, phase: phase)
                    if let pass = Self.pass(probe, route: route, clearance: clearance) {
                        var share: CGFloat = 0.06
                        while share <= 0.9 {
                            let y = water.bottom + (water.top - water.bottom) * share
                            let candidate = hook(kind, role: role, passTime: time, y: y, bait: bait, phase: phase)
                            if apart(candidate) {
                                consider(candidate, pass: pass) { gap in
                                    role == .lane ? -gap - abs(share - 0.5) * 20
                                        : min(gap, T.sunsetOpenGap) - abs(share - 0.5) * 80
                                }
                            } else {
                                rejected["fish", default: 0] += 1
                            }
                            share += 0.03
                        }
                    }
                    time += 0.08
                }
            }
            if let best {
                keep(best.hook)
                rejected.removeAll()
            } else {
                issues.append("no room for hook \(index + 1) (\(kind.rawValue), \(roles[index].rawValue): \(why()))")
            }
        }
        return (placed.sorted { $0.passTime < $1.passTime }, issues)
    }
}
#endif
