import CoreGraphics
import Foundation
import ImageIO
import SpriteKit
import Testing
@testable import BiggerFish

/// Sunset Cove, the prototype world of baited hooks: an easy, a medium, and a hard level, in Xcode builds only.
@MainActor
struct SunsetCoveTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private var plans: [MeetingPlan] { ArcadeWorld.sunsetCove.levels.map { $0.meetingPlan! } }

    /// A level on screen (a scene builds as it's shown), and the view keeping it there.
    private func level(_ index: Int) -> (scene: GameScene, view: SKView) {
        let scene = GameScene(world: .sunsetCove, levelIndex: index, showsJellyLesson: false)
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        return (scene, view)
    }

    /// A hook planned near the end of the lap is, round the loop, just behind where you start. It isn't drawn there,
    /// and can't catch you, until it's coming up along your route (Kraig, Sunset Cove 7: "There's a fish behind me at
    /// the beginning of level 7").
    @Test func aHookAtTheEndOfTheLapIsntBehindYouAtTheStart() throws {
        let (scene, view) = level(6)
        defer { withExtendedLifetime(view) {} }
        scene.debugCaptureRestart()
        scene.debugFrame(seconds: GameTuning.simulationStep)
        let width = GameTuning.playfieldSize.width * CGFloat(GameTuning.sunsetSpecs[6].worldScreens)
        let last = try #require(scene.debugHooks.indices.last)
        // It's planned most of a lap ahead, so round the loop it's on screen behind you...
        #expect(HookMotion.position(scene.debugHooks[last], time: 0).x > width / 2)
        // ...but it isn't drawn, and passing the start doesn't count as passing it.
        #expect(!scene.debugHookShows(last))
        scene.debugAdvance(seconds: 2)
        #expect(scene.debugHookPassedAt(last) == nil)
    }

    /// World 4 of 1.0's five, between Kelp Forest and Midnight Zone, on every build's map: two free levels, the rest with
    /// the unlock, like Jelly Bloom, Kelp Forest, and Midnight Zone.
    @Test func sunsetCoveIsWorldFour() {
        #expect(ArcadeWorld.campaign == [.shallowReef, .jellyBloom, .kelpForest, .sunsetCove, .midnightZone])
        #expect(!ArcadeWorld.prototypes.contains(.sunsetCove))
        #expect(ArcadeWorld.mapWorlds(includingPrototypes: false) == ArcadeWorld.campaign)
        #expect(ArcadeWorld.kelpForest.nextWorld == .sunsetCove && ArcadeWorld.sunsetCove.nextWorld == .midnightZone)
        let world = ArcadeWorld.sunsetCove
        #expect(world.rawValue == "sunset-cove" && world.title == "Sunset Cove" && world.levelCount == 15 && world.deepEndCount == 5)
        #expect(ArcadeUnlock.freeLevels(in: world) == GameTuning.freeLevelsPerWorld)
        #expect(!ArcadeUnlock.needsUnlock(world, GameTuning.freeLevelsPerWorld - 1, unlocked: false, selling: true))
        #expect(ArcadeUnlock.needsUnlock(world, GameTuning.freeLevelsPerWorld, unlocked: false, selling: true))
        #expect(!ArcadeUnlock.needsUnlock(world, GameTuning.freeLevelsPerWorld, unlocked: true, selling: true))
        #expect(ArcadeUnlock.worldsItOpens.contains(world))
        #expect(PlayfieldWater.of(world) == .sunset)
    }

    /// Ten levels and the Deep End: Shallow Reef's fifteen planned just in time, each with every hook its spec asks for.
    @Test func fifteenLevelsPlanWithTheirHooks() {
        #expect(plans.map(\.spec.name) == (1...15).map { "Sunset Cove \($0)" })
        #expect(ArcadeWorld.sunsetCove.levelCount == 15 && ArcadeWorld.sunsetCove.deepEndCount == 5)
        for (index, plan) in plans.enumerated() {
            var spec = plan.spec
            spec.name = GameTuning.reefLabSpecs[index].name
            spec.hooks = nil
            #expect(spec == GameTuning.reefLabSpecs[index])
            #expect(plan.issues.isEmpty && !plan.hasGiantWall, "\(plan.spec.name): \(plan.issues)")
            #expect(plan.fish.contains { ($0.appearsAt ?? 0) > 0 })
            let wanted = plan.spec.hooks!, hooks = plan.hooks ?? []
            let gate = wanted.gate ? 2 : 0
            #expect(hooks.count == wanted.count, "\(plan.spec.name)")
            #expect(hooks.filter { $0.motion == .still }.count == wanted.still + gate, "\(plan.spec.name)")
            #expect(hooks.filter { $0.motion == .bob }.count == wanted.bobbing, "\(plan.spec.name)")
            #expect(hooks.filter { $0.motion == .troll }.count == wanted.trolling, "\(plan.spec.name)")
            #expect(hooks.filter { $0.role == .gate }.count == gate, "\(plan.spec.name)")
            // Bait beside a meal hangs where a meal has a fair spot beside it, and any left over near a lane.
            let beside = hooks.filter { $0.role == .beside }.count
            #expect(wanted.besideMeals == 0 ? beside == 0 : (1...wanted.besideMeals).contains(beside), "\(plan.spec.name)")
        }
        // The first level's hooks hang still, some near your way: the bait is something to leave alone.
        #expect((plans[0].hooks ?? []).allSatisfy { $0.motion == .still })
        // Every level hangs hooks near your way (Kraig got through 1 to 7 unhooked when they hung well clear).
        for plan in plans { #expect((plan.hooks ?? []).contains { $0.role == .lane || $0.role == .gate }, "\(plan.spec.name)") }
        let hooks = plans.map { $0.hooks ?? [] }
        // Bobbing takes a readable three or four seconds; trolling boats motor toward you, slower than you swim, so they
        // go bow first across the screen as everything else does.
        for hook in hooks.joined() where hook.motion == .bob { #expect((3...4).contains(hook.period)) }
        for hook in hooks.joined() where hook.motion == .troll {
            #expect(hook.speed < 0 && -hook.speed < GameTuning.playfieldSize.width / 2.9 / 2)
        }
        // The bait reads as a meal: smaller than you when you pass it.
        for plan in plans {
            let radii = plan.referenceRadii
            for hook in plan.hooks ?? [] where hook.role != .beside {
                let yours = radii[min(radii.count - 1, Int(hook.passTime / GameTuning.simulationStep))]
                #expect(hook.baitRadius < yours, "\(plan.spec.name) hook at \(hook.passTime)")
            }
        }
    }

    /// The trials Kraig's daughters played keep their layouts as levels 2, 5, and 9: each plans as it would under its
    /// old name, fish and hooks both.
    @Test func theTrialsKeepTheirLayouts() {
        for (old, index) in [("Sunset Cove 1", 1), ("Sunset Cove 2", 4), ("Sunset Cove 3", 8)] {
            var spec = GameTuning.sunsetSpecs[index]
            spec.name = old
            let trial = (0..<16).lazy.map { MeetingPlanner.kelpPlan(spec, variation: $0) }.first { $0.issues.isEmpty && !$0.hasGiantWall }
            #expect(plans[index].fish == trial?.fish, "\(plans[index].spec.name)")
            #expect(plans[index].hooks == trial?.hooks, "\(plans[index].spec.name)")
        }
    }

    /// Fairness: the reference route the level was planned on stays open. Every hook keeps clear of every reference
    /// meal's meeting by the margin, along the way or above or below it, and of your way from meal to meal while you
    /// pass it; and every hook comes in from the right with its boat, never out of nowhere.
    @Test func everyHookKeepsClearOfTheReferenceRoute() {
        for (plan, level) in zip(plans, GameTuning.sunsetHooks) {
            let route = HookLayout.Route(fish: plan.fish, crossings: plan.predicted,
                                         timeline: PlayerTimeline.reference(meals: plan.fish.filter(\.referenceMeal).map { ($0.meetingDistance, $0.radius) },
                                             crossSeconds: CGFloat(plan.spec.crossSeconds),
                                             until: GameTuning.playfieldSize.width * CGFloat(plan.spec.worldScreens) * 1.05))
            #expect(route.meals.count == plan.fish.filter(\.referenceMeal).count)
            // A hook retimed by hand is out of the way you can really swim, which isn't the reference route there.
            let retimed = GameTuning.sunsetHooksSweptHigh[plan.spec.name] ?? []
            for (number, hook) in (plan.hooks ?? []).enumerated().map({ ($0.offset + 1, $0.element) }) where !retimed.contains(number) {
                let name = "\(plan.spec.name) \(hook.motion.rawValue) hook at \(String(format: "%.2f", hook.passTime)) s"
                #expect(HookLayout.fits(hook, zoom: route.zoom(hook.passTime)), "\(name) doesn't fit the water")
                for meal in route.meals {
                    #expect(HookLayout.clears(hook, meal: meal, zoom: route.zoom(meal.time)),
                            "\(name) crowds the meal at \(meal.time) s")
                }
                let window = hook.role == .gate ? GameTuning.sunsetGateWindow : GameTuning.sunsetPassWindow
                #expect(HookLayout.gap(hook, route: route, clearance: CGFloat(level.clearance), window: window) >= 0,
                        "\(name) is in your way")
                // On screen, its boat first, at least a second and a half before you reach it.
                var time = max(0, hook.passTime - 4)
                while time < hook.passTime {
                    let edge = route.distance(time) + GameTuning.playfieldSize.width * (1 - GameTuning.playerScreenX) / route.zoom(time)
                    if HookMotion.rodX(hook, time: time) <= edge { break }
                    time += GameTuning.simulationStep
                }
                #expect(hook.passTime - time >= 1.5, "\(name) shows only \(hook.passTime - time) s ahead")
                #expect(HookMotion.rodX(hook, time: time) <= HookMotion.position(hook, time: time).x)
            }
        }
    }

    /// A hook retimed by hand (`sunsetHooksSweptHigh`) is a trolling hook at the top of its sweep as you pass it, its
    /// boat and sweep as planned. In Sunset Cove 15 that leaves the floor open under the big fish that comes at you
    /// beneath the giant.
    @Test func retimedHooksSweepHighAsYouPass() throws {
        #expect(GameTuning.sunsetHooksSweptHigh["Sunset Cove 15"] == [4])
        for (name, numbers) in GameTuning.sunsetHooksSweptHigh {
            let index = try #require(GameTuning.sunsetSpecs.firstIndex { $0.name == name })
            let planned = plans[index].hooks ?? []
            for number in numbers {
                let hook = try #require(planned.indices.contains(number - 1) ? planned[number - 1] : nil)
                #expect(hook.motion == .troll, "\(name) hook \(number)")
                #expect(abs(HookMotion.position(hook, time: hook.passTime).y - (hook.depth + hook.range)) < 0.01, "\(name) hook \(number)")
            }
        }
    }

    /// Touching the bait or the hook's bend catches you: you're reeled up and out, and the card says why. The line
    /// doesn't.
    @Test func touchingAHookOrItsBaitCatchesYou() {
        for part in [GameScene.HookPart.bait, .bend] {
            let (scene, view) = level(2)
            scene.debugStart()
            #expect(scene.debugTouchHook(0, at: part), "\(part)")
            #expect(scene.debugPhase == .lost && scene.debugReeling && scene.debugLossReason == "Caught on a hook.")
            // The card waits for the reel.
            #expect(scene.debugResultTitles.isEmpty)
            scene.debugAdvance(seconds: GameTuning.sunsetReelSeconds)
            #expect(scene.debugResultTitles.isEmpty)
            scene.debugAdvance(seconds: GameTuning.sunsetReelResultDelay - GameTuning.sunsetReelSeconds + 0.1)
            #expect(!scene.debugResultTitles.isEmpty)
            // Retry puts the bait back and you back in the water.
            scene.debugTapResult(.tryAgain)
            #expect(!scene.debugReeling && scene.debugLossReason != "Caught on a hook.")
            withExtendedLifetime(view) {}
        }
        let (scene, view) = level(0)
        scene.debugStart()
        #expect(!scene.debugTouchHook(0, at: .line))
        #expect(scene.debugPhase == .playing)
        withExtendedLifetime(view) {}
    }

    /// Other fish never take the bait: a fish held on a hook's bait swims on, and the hook stays baited.
    @Test func otherFishPassHooksUnharmed() {
        for index in 0..<ArcadeWorld.sunsetCove.levelCount {
            let (scene, view) = level(index)
            defer { withExtendedLifetime(view) {} }
            scene.debugStart()
            // Hooks aren't fish: nothing can eat a bait, and a bait can't eat anything.
            #expect(scene.debugFishCount == ArcadeWorld.sunsetCove.level(index).meetingPlan!.fish.filter { ($0.appearsAt ?? 0) <= 0 }.count + 1)
            // Some levels start with every fish still to swim in: on until the first does.
            for _ in 0..<50 where scene.debugFishCount < 2 { scene.debugAdvance(seconds: 0.1) }
            for hook in scene.debugHooks.indices {
                #expect(scene.debugFishPassesHook(hook, seconds: 0.25), "Sunset Cove \(index + 1) hook \(hook)")
            }
        }
    }

    /// A campaign world reports, a death on a hook as cause "hook" (the stats server takes it from 1.0). A prototype
    /// world never reports: the server would drop the whole batch over a world or cause it doesn't know.
    @Test(arguments: [ArcadeWorld.sunsetCove, .riptideReef]) func campaignWorldsReportAndPrototypesDont(_ world: ArcadeWorld) async {
        let sender = ArcadeMetricsTests.Sender()
        let defaults = UserDefaults(suiteName: "metrics.tests.\(UUID().uuidString)")!
        let analytics = ArcadeAnalytics(defaults: defaults, sender: sender, enabled: true)
        let scene = GameScene(world: world, levelIndex: 0)
        scene.analytics = analytics
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        scene.debugStart()
        if world == .sunsetCove {
            #expect(scene.debugTouchHook(0, at: .bait))
        } else {
            scene.debugLose()
        }
        scene.debugAdvance(seconds: 1.5)
        scene.debugTapResult(.tryAgain)
        scene.debugStart()
        scene.exitMetrics()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let events = analytics.queue + sender.batches.flatMap(\.events)
        if world == .sunsetCove {
            #expect(events.contains { $0.kind == .run && $0.outcome == "death" && $0.cause == "hook" && $0.context?.world == "sunset-cove" })
        } else {
            #expect(events.isEmpty)
        }
        withExtendedLifetime(view) {}
    }

    /// Each level, played by a bot that swims the reference route (a straight swim from each meeting to the next),
    /// steering round hooks. With nothing able to eat it, so the run tests the hooks rather than the bot, it eats every
    /// meal on the route: the hooks never block it, which is what the planner promises. What the bot does after that,
    /// cleaning up, or played for real, says more about the bot than the level (Kraig: "some of the best levels the bot
    /// loses"), so it isn't checked.
    @Test(arguments: Array(0..<15)) func eachLevelsRouteStaysOpen(_ index: Int) {
        let (scene, view) = level(index)
        defer { withExtendedLifetime(view) {} }
        let plan = scene.debugMeetingPlan!
        let safe = scene.debugPlayReferenceRoute(safeFromFish: true)
        let route = Set(plan.fish.filter(\.referenceMeal).map(\.id))
        #expect(route.isSubset(of: scene.debugMealLog.map(\.id)),
                "Sunset Cove \(index + 1) missed \(route.subtracting(scene.debugMealLog.map(\.id))): \(safe)")
    }

    /// A line hangs from its own boat's rod, so on screen it's never wider than a trolling hook trails behind its boat,
    /// wherever the hook is on the lap. (Rod and hook were each placed on screen the shorter way round the lap from you,
    /// so a hook half a lap away hung its line from the far side: Kraig saw "a random line that appears across the
    /// screen almost horizontally" in level 3.)
    @Test(arguments: Array(0..<15)) func hookLinesHangFromTheirOwnBoats(_ index: Int) {
        let (scene, view) = level(index)
        defer { withExtendedLifetime(view) {} }
        var widest: CGFloat = 0
        _ = scene.debugPlayReferenceRoute(limit: 40, safeFromFish: true) {
            scene.debugRender()
            widest = max(widest, scene.debugHookLineWidths.max() ?? 0)
        }
        #expect(widest <= GameTuning.sunsetTrollTrail + 1, "Sunset Cove \(index + 1): a hook line \(Int(widest)) points wide")
    }

    /// Frozen levels play their saved plans, not fresh ones, and `SunsetPlans.json` holds a plan for every level's
    /// current settings: change a level's settings and the file must be regenerated.
    @Test func frozenLevelsPlayTheirSavedPlans() throws {
        let url = try #require(Bundle.main.url(forResource: "SunsetPlans", withExtension: "json"))
        let bundled = try JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: url))
        #expect(bundled.map(\.spec) == GameTuning.sunsetSpecs, "SunsetPlans.json is out of date: regenerate it")
        #expect(GameTuning.sunsetFrozen.isSubset(of: GameTuning.sunsetSpecs.map(\.name)))
        #expect(GameTuning.sunsetFrozen == Set(GameTuning.sunsetSpecs.map(\.name)))
        for (index, plan) in plans.enumerated() where GameTuning.sunsetFrozen.contains(plan.spec.name) {
            #expect(plan.fish == bundled[index].fish && plan.hooks == bundled[index].hooks, "\(plan.spec.name)")
        }
        // Sunset Cove 10's giants were sized by hand so they finish edible (`sunsetFishRadius`).
        #expect(plans[9].variation == 9 && plans[9].fish[9].radius == 63 && plans[9].fish[15].radius == 61.5)
    }

    /// Writes BiggerFish/SunsetPlans.json when build/arcade-development/sunset-plans.request exists. Frozen levels keep
    /// their saved plans; the rest are planned in code (`GameTuning.sunsetPlan`).
    @Test func manualWriteSunsetPlans() throws {
        let marker = Self.root.appendingPathComponent("build/arcade-development/sunset-plans.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let file = Self.root.appendingPathComponent("BiggerFish/SunsetPlans.json")
        let existing = (try? JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: file))) ?? []
        let plans = GameTuning.sunsetSpecs.indices.map { index in
            let spec = GameTuning.sunsetSpecs[index]
            return GameTuning.sunsetFrozen.contains(spec.name) ? existing.first { $0.spec == spec } ?? GameTuning.sunsetPlan(index)
                : GameTuning.sunsetPlan(index)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(plans).write(to: file)
        try FileManager.default.removeItem(at: marker)
    }

    /// Once you've passed a hook, its boat reels the line up: on later laps the bait hangs just under the surface and the
    /// water below is yours (Kraig, Sunset Cove 13: "you can't really dive in and out because you're so big and the
    /// hooks are so close"). Passed means gone off the left of your screen, however far behind the planned route you
    /// are, so until then it hangs exactly as planned and the first pass is unchanged.
    @Test func passedHooksReelUpNearTheSurface() {
        let (scene, view) = level(12)
        defer { withExtendedLifetime(view) {} }
        let hooks = scene.debugHooks
        var drift: CGFloat = 0, lowest: [Int: CGFloat] = [:], passed: [Int: CGFloat] = [:]
        _ = scene.debugPlayReferenceRoute(limit: 30, safeFromFish: true) {
            let t = CGFloat(scene.debugGameplayClock)
            for (index, hook) in hooks.enumerated() {
                guard let at = scene.debugHookPassedAt(index) else {
                    drift = max(drift, abs(scene.debugHookPosition(index).y - HookMotion.position(hook, time: t).y))
                    continue
                }
                passed[index] = at
                if t > at + GameTuning.sunsetReelUpAfter + GameTuning.sunsetReelUpSeconds {
                    lowest[index] = min(lowest[index] ?? 1, scene.debugHookDepthShare(index))
                }
            }
        }
        #expect(drift < 0.5, "a hook moved before you'd passed it (\(drift))")
        // Passed only once you're well beyond it: after the planned route reaches it, and then off the screen.
        for (index, at) in passed { #expect(at > hooks[index].passTime, "hook \(index) counted passed at \(at) s, before \(hooks[index].passTime) s") }
        #expect(lowest.count >= hooks.count - 2, "only \(lowest.count) of \(hooks.count) hooks were seen reeled up")
        for (index, share) in lowest { #expect(share > 0.85, "hook \(index) hangs at \(share) of the water once reeled up") }
    }

    // MARK: Previews

    /// Renders Sunset Cove's key moments to build/previews/sunset-cove-*.png, with a contact sheet, when xcodebuild
    /// runs with `TEST_RUNNER_SUNSET_COVE_PREVIEWS=1`.
    @Test func manualRenderSunsetCovePreviews() throws {
        guard ProcessInfo.processInfo.environment["SUNSET_COVE_PREVIEWS"] == "1" else { return }
        let folder = Self.root.appendingPathComponent("build/previews")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var frames: [(name: String, image: CGImage)] = []
        func save(_ scene: GameScene, _ view: SKView, _ name: String) throws {
            scene.debugRender()
            let image = try #require(view.texture(from: scene)?.cgImage())
            try write(image, to: folder.appendingPathComponent("sunset-cove-\(name).png"))
            frames.append((name, image))
        }
        for index in 0..<ArcadeWorld.sunsetCove.levelCount {
            let (scene, view) = level(index)
            defer { withExtendedLifetime(view) {} }
            try save(scene, view, "\(index + 1)-card")
            // Played along the route, a frame as each hook comes near (a second before you pass it).
            let hooks = scene.debugHooks
            var shots = hooks.indices.map { (hook: $0, at: max(0.5, hooks[$0].passTime - 1.0), shot: false) }
            _ = scene.debugPlayReferenceRoute(limit: (hooks.map(\.passTime).max() ?? 10) + 1, safeFromFish: true) {
                for i in shots.indices where !shots[i].shot && scene.debugGameplayClock >= Double(shots[i].at) {
                    shots[i].shot = true
                    let hook = hooks[shots[i].hook]
                    try? save(scene, view, "\(index + 1)-hook\(shots[i].hook + 1)-\(hook.motion.rawValue)-\(hook.role.rawValue)")
                }
            }
        }
        // Caught: the reel-up, a frame every tenth of a second, then the card.
        let (scene, view) = level(0)
        let first = scene.debugHooks[0]
        _ = scene.debugPlayReferenceRoute(limit: first.passTime - 0.9)
        #expect(scene.debugTouchHook(0, at: .bait))
        for tenth in 0...9 {
            try save(scene, view, "reel-\(tenth)")
            scene.debugAdvance(seconds: 0.1)
        }
        scene.debugAdvance(seconds: 0.4)
        try save(scene, view, "reel-card")
        withExtendedLifetime(view) {}
        try write(contactSheet(frames), to: folder.appendingPathComponent("sunset-cove-contact-sheet.png"))
        // Each level's hooks, in words.
        let summary = plans.map { plan in
            let radii = plan.referenceRadii
            let lines = (plan.hooks ?? []).map { hook -> String in
                let yours = radii[min(radii.count - 1, Int(hook.passTime / GameTuning.simulationStep))]
                return String(format: "  %.1f s: %@, %@, bait %.0f%% of you (radius %.0f)", Double(hook.passTime),
                              hook.motion.rawValue, hook.role.rawValue, Double(hook.baitRadius / yours * 100), Double(hook.baitRadius))
            }
            return "\(plan.spec.name) (variation \(plan.variation), \(plan.fish.count) fish):\n" + lines.joined(separator: "\n")
        }
        try summary.joined(separator: "\n").write(to: folder.appendingPathComponent("sunset-cove-hooks.txt"), atomically: true, encoding: .utf8)
    }

    private func contactSheet(_ frames: [(name: String, image: CGImage)]) throws -> CGImage {
        let columns = 4, scale: CGFloat = 0.5
        let width = CGFloat(frames[0].image.width) * scale, height = CGFloat(frames[0].image.height) * scale
        let rows = (frames.count + columns - 1) / columns
        let context = try #require(CGContext(data: nil, width: Int(width) * columns, height: Int(height) * rows,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width * CGFloat(columns), height: height * CGFloat(rows)))
        context.interpolationQuality = .high
        for (index, frame) in frames.enumerated() {
            let column = index % columns, row = rows - 1 - index / columns
            context.draw(frame.image, in: CGRect(x: CGFloat(column) * width, y: CGFloat(row) * height, width: width, height: height)
                .insetBy(dx: 2, dy: 2))
        }
        return try #require(context.makeImage())
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
