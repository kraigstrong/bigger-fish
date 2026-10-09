import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

private final class BundleToken {}

extension GameScene {
    static func plannerScene(_ spec: MeetingSpec, variation: Int = 0) -> GameScene {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        scene.debugUsePlanner(spec, variation: variation)
        return scene
    }
}

struct MeetingPlannerTests {
    private static func crossing(_ id: Int, at time: Double, y: Double = 200, radius: Double) -> EncounterCrossing {
        EncounterCrossing(fishID: id, time: time, distance: time * 300, y: y, radius: radius, headOn: true, zoom: 1)
    }

    @Test func analyzerFindsFewestMealsRoutesAndMissesSurvived() {
        // Three level foods, then a gate any one of them makes edible.
        let analysis = EncounterAnalyzer.analyze([
            Self.crossing(1, at: 1, radius: 10), Self.crossing(2, at: 1.6, radius: 10),
            Self.crossing(3, at: 2.2, radius: 10), Self.crossing(4, at: 3, radius: 17),
        ])
        let gate = analysis.meeting(fishID: 4)!
        #expect(analysis.meeting(fishID: 1)?.minimumMeals == 0)
        #expect(gate.minimumMeals == 1 && gate.maximumMeals == 3 && gate.routes == 3)
        // You'd have to miss all three foods.
        #expect(gate.robustSlack == 2)
        #expect(analysis.maximumMeals == 4 && analysis.fullestRoute == [1, 2, 3, 4])
    }

    @Test func analyzerRespectsSwallowTimeReachAndCrowdedCrossings() {
        // A near-equal swallow (about 0.7 s) blocks a meal 0.3 s later.
        let swallow = EncounterAnalyzer.analyze([Self.crossing(1, at: 1, radius: 15), Self.crossing(2, at: 1.3, radius: 8)])
        #expect(swallow.maximumMeals == 1)
        // Two foods at the same moment, top and bottom of the water: one or the other.
        let split = EncounterAnalyzer.analyze([Self.crossing(1, at: 1.5, y: 40, radius: 9), Self.crossing(2, at: 1.5, y: 360, radius: 9)])
        #expect(split.maximumMeals == 1 && split.meeting(fishID: 1)?.routes == 1)
        // A bigger fish crossing on top of a food makes it uneatable; slightly off, it's a danger meal.
        let blocked = EncounterAnalyzer.analyze([Self.crossing(1, at: 1.5, radius: 9), Self.crossing(2, at: 1.52, radius: 30)])
        #expect(blocked.meeting(fishID: 1)?.minimumMeals == nil)
        let danger = EncounterAnalyzer.analyze([Self.crossing(1, at: 1.5, radius: 9), Self.crossing(2, at: 1.7, y: 300, radius: 30)])
        #expect(danger.meeting(fishID: 1)?.danger == true)
    }

    @Test func analyzerRoutesOverUnderAndOffJellies() {
        // A bell across mid-water as you pass it at 2 s: its tentacles hang from 130 to its rim at 200.
        let jelly = JellyPass(jellyID: 0, time: 2, rim: 200, domeRadius: 40, tentacleLength: 70, speed: 300, zoom: 1)
        let open = EncounterAnalyzer.analyze([Self.crossing(1, at: 2.1, y: 180, radius: 9)])
        let stung = EncounterAnalyzer.analyze([Self.crossing(1, at: 2.1, y: 180, radius: 9)], jellies: [jelly])
        #expect(open.meeting(fishID: 1)?.minimumMeals == 0 && stung.meeting(fishID: 1)?.minimumMeals == nil)
        // Over the dome or under the tentacles is fine.
        let around = EncounterAnalyzer.analyze([Self.crossing(1, at: 2.1, y: 300, radius: 9),
                                                Self.crossing(2, at: 2.6, y: 60, radius: 9)], jellies: [jelly])
        #expect(around.meeting(fishID: 1)?.minimumMeals == 0 && around.meeting(fishID: 2)?.minimumMeals == 0)
        // From a meal on the dome, a meal high above it half a second later takes the bounce.
        let pocket = Self.crossing(1, at: 1.95, y: 250, radius: 10), high = Self.crossing(2, at: 2.4, y: 370, radius: 10)
        let reach = EncounterAnalyzer.reach(from: pocket, to: high, jellies: [jelly], radius: 18)
        #expect(!reach.swim && reach.bounce)
        #expect(EncounterAnalyzer.analyze([pocket, high], jellies: [jelly]).meeting(fishID: 2)?.maximumMeals == 1)
        // Another curtain right after the bounce, across everywhere it could carry you: no way through.
        let next = JellyPass(jellyID: 1, time: 2.2, rim: 300, domeRadius: 40, tentacleLength: 70, speed: 300, zoom: 1)
        #expect(!EncounterAnalyzer.reach(from: pocket, to: high, jellies: [jelly, next], radius: 18).bounce)
    }

    @Test func reefLabPlansCleanlyAndGetsHarderLevelByLevel() {
        let specs = GameTuning.reefLabSpecs
        let plans = GameTuning.reefLabLevels.map { $0.meetingPlan! }
        for plan in plans {
            #expect(plan.fish.map(\.id) == Array(1...plan.fish.count))
            #expect(plan.analysis.meetings.filter { $0.minimumMeals != nil }.count > plan.fish.count / 2)
        }
        // Today's planner places every big fish a spec asks for, with at most one fish slightly off its plan.
        for spec in specs {
            let plan = MeetingPlanner.plan(spec)
            let walls = plan.fish.filter { $0.role == .threat }.count
                - spec.extraThreats - spec.segments.reduce(0) { $0 + $1.dangerFoods }
            #expect(walls >= 0, "\(spec.name) is missing big fish")
            #expect(plan.issues.count <= 1 && plan.issues.allSatisfy { $0.contains("is off its plan") }, "\(spec.name): \(plan.issues)")
        }
        let tightest = plans.map { plan in
            plan.fish.filter { $0.role == .gate }.compactMap { plan.analysis.meeting(fishID: $0.id)?.robustSlack }.min() ?? -1
        }
        // Levels 2, 6, and 10 are the playtested Easy, Medium, and Hard.
        #expect(tightest[1] >= tightest[5] && tightest[5] >= tightest[9] && tightest[1] > tightest[9])
        #expect([specs[1].name, specs[5].name, specs[9].name] == ["Easy", "Medium", "Hard"])
        // The first ten ramp up; the bonus levels after them each have their own feel at levels 8–10's difficulty.
        let campaign = specs.prefix(10)
        for (previous, next) in zip(campaign, campaign.dropFirst()) {
            #expect(next.aiSpeed.upperBound > previous.aiSpeed.upperBound && next.crossSeconds < previous.crossSeconds)
            #expect(next.gateMargin < previous.gateMargin && next.dangerGap < previous.dangerGap)
        }
        #expect(GameTuning.reefLabFrozen.isSubset(of: specs.map(\.name)))
    }

    /// Open-water threats never land beside each other, even when one moves earlier into another's slot.
    @Test func plannedThreatsNeverCrossOnTopOfEachOther() {
        for spec in GameTuning.reefLabSpecs {
            let plan = MeetingPlanner.plan(spec)
            let crossings = Dictionary(uniqueKeysWithValues: plan.predicted.map { ($0.fishID, $0) })
            let threats = plan.fish.filter { $0.role == .threat }
            for (offset, a) in threats.enumerated() {
                for b in threats.dropFirst(offset + 1) {
                    let first = crossings[a.id]!, second = crossings[b.id]!
                    guard abs(first.time - second.time) < 0.15 else { continue }
                    #expect(abs(first.y - second.y) >= Double(a.radius + b.radius) * Double(GameTuning.collisionScale),
                            "\(spec.name): threats \(a.id) and \(b.id) cross on top of each other")
                }
            }
        }
    }

    @MainActor @Test func plannedFishMeetThePlayerWherePlannedOnAnyRoute() {
        // The shipped Easy, Medium, and Hard, in the real Reef Lab world.
        for index in [1, 5, 9] {
            let plan = GameTuning.reefLabLevels[index].meetingPlan!
            let spec = plan.spec
            let reference = Set(plan.fish.filter(\.referenceMeal).map(\.id))
            let scene = GameScene(world: .shallowReef, levelIndex: index)
            let actual = scene.debugEncounterCrossings(radii: plan.referenceRadii, eaten: reference)
            for predicted in plan.predicted {
                let real = actual.first { $0.fishID == predicted.fishID }
                #expect(real.map { abs($0.time - predicted.time) < 0.05 && abs($0.y - predicted.y) < 3 } == true,
                        "\(spec.name) fish \(predicted.fishID)")
            }
            #expect(scene.debugVisibleUnmetContacts == 0)
            // A player who eats only what each gate needs, or everything, still meets every fish.
            for route in [plan.fewestMealRoute, plan.fullestRoute] {
                let crossings = GameScene(world: .shallowReef, levelIndex: index).debugEncounterCrossings(radii: plan.radii(eating: route), eaten: route)
                #expect(Set(crossings.map(\.fishID)) == Set(plan.fish.map(\.id)), "\(spec.name)")
            }
        }
    }

    /// Planned fish that touch where you could see it push apart and lose their meetings, and a player who eats
    /// more zooms out and sees further. Gauntlet's first giants knocked each other into an impassable wall.
    @MainActor @Test func bonusLevelsFishDontBumpOnTheWayToTheirMeetings() {
        for world in [ArcadeWorld.shallowReef, .jellyBloom] {
            for index in 10..<world.levelCount {
                let plan = world.level(index).meetingPlan!
                let reference = Set(plan.fish.filter(\.referenceMeal).map(\.id))
                for route in [plan.fewestMealRoute, reference, plan.fullestRoute] {
                    let scene = GameScene(world: world, levelIndex: index)
                    let crossings = scene.debugEncounterCrossings(radii: plan.radii(eating: route), eaten: route)
                    #expect(Set(crossings.map(\.fishID)) == Set(plan.fish.map(\.id)), "\(plan.spec.name)")
                    // Eating everything zooms out furthest; a couple of brushes there is as good as Hard does.
                    // Jelly Frenzy shipped as Kraig played and liked it, with three brushes on every route.
                    let played = plan.spec.name == "Jelly Frenzy" ? 3 : 0
                    #expect(scene.debugVisibleUnmetContacts <= max(played, route == plan.fullestRoute ? 2 : 0),
                            "\(plan.spec.name)")
                }
            }
        }
    }

    /// Midnight Zone plans like Kelp Forest without kelp: clean layouts following Shallow Reef's levels, Deep End
    /// included, whose fish appear just off screen. Levels 1, 5, and 9 keep the trials Kraig played (planned as
    /// levels 1, 2, and 3).
    @MainActor @Test func midnightZonePlansCleanJustInTimeLevels() {
        let plans = ArcadeWorld.midnightZone.levels.map { $0.meetingPlan! }
        #expect(plans.map(\.spec.name) == (1...15).map { "Midnight Zone \($0)" })
        #expect(ArcadeWorld.midnightZone.deepEndCount == 5)
        #expect(zip(plans, [0, 1, 2, 3, 4, 6, 7, 8, 9, 9, 10, 11, 12, 13, 14]).allSatisfy { plan, source in
            var spec = plan.spec
            spec.name = GameTuning.reefLabSpecs[source].name
            return spec == GameTuning.reefLabSpecs[source]
        })
        #expect(plans.allSatisfy { $0.issues.isEmpty && !$0.hasGiantWall && ($0.kelp ?? []).isEmpty && $0.spec.reachScale == 1 })
        #expect(plans.allSatisfy { $0.fish.contains { ($0.appearsAt ?? 0) > 0 } })
        #expect(plans[8].fish != plans[9].fish)
        for (level, trial, source) in [(0, "Midnight Zone 1", 0), (4, "Midnight Zone 2", 4), (8, "Midnight Zone 3", 9)] {
            var spec = GameTuning.reefLabSpecs[source]
            spec.name = trial
            let played = (0..<16).lazy.map { MeetingPlanner.kelpPlan(spec, variation: $0) }.first { $0.issues.isEmpty && !$0.hasGiantWall }!
            #expect(plans[level].fish == played.fish && plans[level].seed == played.seed, "\(trial)")
        }
        #expect(!ArcadeWorld.campaign.contains(.midnightZone) && ArcadeWorld.mapWorlds.last == .midnightZone)
    }

    @Test func bundledMidnightPlansMatchTheSpecs() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "MidnightPlans", withExtension: "json")
            ?? Bundle.main.url(forResource: "MidnightPlans", withExtension: "json"))
        let bundled = try JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: url))
        #expect(bundled.map(\.spec) == GameTuning.midnightSpecs, "MidnightPlans.json is out of date: regenerate it")
        #expect(GameTuning.midnightFrozen.isSubset(of: GameTuning.midnightSpecs.map(\.name)))
        // What ships is the saved data, not a fresh plan.
        for (index, level) in ArcadeWorld.midnightZone.levels.enumerated() where GameTuning.midnightFrozen.contains(level.meetingPlan!.spec.name) {
            #expect(level.meetingPlan!.fish == bundled[index].fish, "\(bundled[index].spec.name)")
        }
    }

    /// Writes BiggerFish/MidnightPlans.json when build/arcade-development/midnight-plans.request exists. Frozen
    /// levels keep their saved plans; the rest are planned in code (`GameTuning.midnightPlan`).
    @Test func manualWriteMidnightPlans() throws {
        let marker = Self.root.appendingPathComponent("build/arcade-development/midnight-plans.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let file = Self.root.appendingPathComponent("BiggerFish/MidnightPlans.json")
        let existing = (try? JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: file))) ?? []
        let plans = GameTuning.midnightSpecs.indices.map { index in
            let spec = GameTuning.midnightSpecs[index]
            return GameTuning.midnightFrozen.contains(spec.name) ? existing.first { $0.spec == spec } ?? GameTuning.midnightPlan(index)
                : GameTuning.midnightPlan(index)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(plans).write(to: file)
    }

    /// Kelp Forest's fish appear just off screen and follow their approach in, so every one meets the reference
    /// route exactly as planned, kelp or not.
    @MainActor @Test func kelpForestFishMeetYouExactlyWherePlanned() {
        // Fish come in every way, not all along a straight line.
        let styles = Set(ArcadeWorld.kelpForest.levels.flatMap { $0.meetingPlan!.fish.compactMap(\.approach?.style) })
        #expect(styles == [.glide, .weave, .turn])
        // No two giants beside you at once wall off the water (Kelp Forest 13's first layout did).
        #expect(ArcadeWorld.kelpForest.levels.allSatisfy { !$0.meetingPlan!.hasGiantWall })
        #expect(MeetingPlanner.kelpPlan(GameTuning.kelpSpecs[12], variation: 0).hasGiantWall)
        // Every fish appears inside the water you can see then, and none is swimming away when the level starts
        // (one that turned late outran you along the surface of level 7).
        for level in ArcadeWorld.kelpForest.levels {
            let plan = level.meetingPlan!
            for fish in plan.fish {
                #expect(!(fish.appearsAt == 0 && fish.approach?.style == .turn), "\(plan.spec.name) fish \(fish.id)")
                if fish.appearsAt == 0 {
                    let water = PlayerTimeline.waterBounds(zoom: 1)
                    #expect((water.bottom...water.top).contains(fish.spawn.y), "\(plan.spec.name) fish \(fish.id) starts at y \(fish.spawn.y)")
                }
            }
        }
        for index in [0, ArcadeWorld.kelpForest.levelCount - 1] {
            let plan = ArcadeWorld.kelpForest.level(index).meetingPlan!
            #expect(plan.fish.allSatisfy { $0.appearsAt != nil } && !(plan.kelp ?? []).isEmpty)
            let route = Set(plan.fish.filter(\.referenceMeal).map(\.id))
            let crossings = GameScene(world: .kelpForest, levelIndex: index)
                .debugEncounterCrossings(radii: plan.radii(eating: route), eaten: route)
            for predicted in plan.predicted {
                let real = crossings.first { $0.fishID == predicted.fishID }
                #expect(real.map { abs($0.time - predicted.time) < 0.02 && abs($0.y - predicted.y) < 1 } == true,
                        "\(plan.spec.name) fish \(predicted.fishID)")
            }
        }
    }

    @MainActor @Test func shallowReefPlaysFifteenPlannedLevelsThatUnlockAndResetLikeACampaign() {
        #expect(Array(ArcadeWorld.mapWorlds.prefix(3)) == [.shallowReef, .jellyBloom, .kelpForest])
        #expect(ArcadeWorld.jellyBloom.levels.allSatisfy { $0.meetingPlan != nil && $0.jellies != nil })
        let world = ArcadeWorld.shallowReef
        #expect(world.levelCount == 15 && world.levelTitles == (1...15).map { "Level \($0)" })
        #expect(world.levels.allSatisfy { $0.meetingPlan != nil && $0.jellies == nil })
        let progress = ArcadeProgress(defaults: UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!)
        #expect(progress.isOpen(world, 0) && !progress.isOpen(world, 1) && !progress.isOpen(world, 10))
        progress.clear(world, 0, seconds: 20)
        progress.clear(.jellyBloom, 0, seconds: 30)
        #expect(progress.isOpen(world, 1) && progress.save.bestTimes["shallow-reef.1"] == 20)
        progress.reset(world)
        #expect(!progress.isCleared(world, 0) && progress.save.bestTimes["shallow-reef.1"] == nil)
        #expect(progress.isCleared(.jellyBloom, 0))
        let scene = GameScene(world: world, levelIndex: 5)
        #expect(scene.debugEncounterCrossings(laps: 0.01).isEmpty)
        #expect(scene.debugFishCount == world.level(5).meetingPlan!.fish.count + 1)
        #expect(scene.debugMeetingPlan?.spec.name == "Medium")
    }

    /// The shipped plans must be what the planner makes today; regenerate them with the marker below.
    @Test func bundledReefLabPlansMatchThePlanner() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "ReefLabPlans", withExtension: "json")
            ?? Bundle.main.url(forResource: "ReefLabPlans", withExtension: "json"))
        let bundled = try JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: url))
        #expect(bundled.map(\.spec) == GameTuning.reefLabSpecs, "ReefLabPlans.json is out of date: regenerate it")
        // Frozen levels keep their playtested plans; the rest are what the planner makes today.
        for plan in bundled where !GameTuning.reefLabFrozen.contains(plan.spec.name) {
            #expect(plan.fish == MeetingPlanner.plan(plan.spec).fish, "\(plan.spec.name): regenerate ReefLabPlans.json")
        }
    }

    /// Writes BiggerFish/ReefLabPlans.json when build/arcade-development/reef-lab-plans.request exists.
    @Test func manualWriteReefLabPlans() throws {
        let marker = Self.root.appendingPathComponent("build/arcade-development/reef-lab-plans.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let file = Self.root.appendingPathComponent("BiggerFish/ReefLabPlans.json")
        let existing = (try? JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: file))) ?? []
        let plans = GameTuning.reefLabSpecs.map { spec in
            // A frozen level keeps its shipped plan; changing its spec means unfreezing it to re-plan.
            GameTuning.reefLabFrozen.contains(spec.name) ? existing.first { $0.spec.name == spec.name }.map { frozen in
                MeetingPlan(spec: spec, variation: frozen.variation, seed: frozen.seed, fish: frozen.fish,
                            predicted: frozen.predicted, analysis: frozen.analysis, issues: frozen.issues)
            } ?? MeetingPlanner.plan(spec) : MeetingPlanner.plan(spec)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(plans).write(to: file)
    }

    /// Jelly Bloom 2 ships its plans too. Replanning ten jelly levels is slow, so this checks they're
    /// current with the specs; regenerate with the marker below after changing a spec or the planner.
    @Test func bundledJellyLabPlansMatchTheSpecs() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "JellyLabPlans", withExtension: "json")
            ?? Bundle.main.url(forResource: "JellyLabPlans", withExtension: "json"))
        let bundled = try JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: url))
        #expect(bundled.map(\.spec) == GameTuning.jellyLabSpecs, "JellyLabPlans.json is out of date: regenerate it")
        #expect(GameTuning.jellyLabFrozen.isSubset(of: GameTuning.jellyLabSpecs.map(\.name)))
        for plan in bundled {
            #expect(plan.fish.map(\.id) == Array(1...plan.fish.count))
            // Scattered open-water jellies fill what room there is, so a shortfall there is fine.
            #expect(plan.issues.allSatisfy { $0.contains("is off its plan") || $0.contains("open-water jellies fit") },
                    "\(plan.spec.name): \(plan.issues)")
        }
    }

    /// Writes BiggerFish/JellyLabPlans.json when build/arcade-development/jelly-lab-plans.request exists. The
    /// marker may say "quick" (a playtest plan from a few layouts, about a minute) and "variation N" (another
    /// layout from the same settings) for the levels being replanned.
    @Test func manualWriteJellyLabPlans() throws {
        let marker = Self.root.appendingPathComponent("build/arcade-development/jelly-lab-plans.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let words = ((try? String(contentsOf: marker, encoding: .utf8)) ?? "").split(whereSeparator: \.isWhitespace)
        let attempts = words.contains("quick") ? MeetingPlanner.quickDesignAttempts : nil
        let variation = words.firstIndex(of: "variation").flatMap { words.dropFirst($0 + 1).first.flatMap { Int($0) } } ?? 0
        let file = Self.root.appendingPathComponent("BiggerFish/JellyLabPlans.json")
        let existing = (try? JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: file))) ?? []
        // Frozen levels keep their shipped plans.
        let plans = GameTuning.jellyLabSpecs.map { spec in
            GameTuning.jellyLabFrozen.contains(spec.name) ? existing.first { $0.spec == spec } ?? MeetingPlanner.plan(spec)
                : MeetingPlanner.plan(spec, variation: variation, attempts: attempts)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(plans).write(to: file)
    }

    /// Kelp Forest ships its played levels as data, so a planner change can't alter them. A test that fails here
    /// means the specs changed without regenerating: use the marker below.
    @Test func bundledKelpPlansMatchTheSpecs() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "KelpPlans", withExtension: "json")
            ?? Bundle.main.url(forResource: "KelpPlans", withExtension: "json"))
        let bundled = try JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: url))
        #expect(bundled.map(\.spec) == GameTuning.kelpSpecs, "KelpPlans.json is out of date: regenerate it")
        #expect(GameTuning.kelpFrozen.isSubset(of: GameTuning.kelpSpecs.map(\.name)))
        // What ships is the saved data, not a fresh plan.
        for (index, level) in ArcadeWorld.kelpForest.levels.enumerated() where GameTuning.kelpFrozen.contains(level.meetingPlan!.spec.name) {
            #expect(level.meetingPlan!.fish == bundled[index].fish, "\(bundled[index].spec.name)")
        }
    }

    /// Writes BiggerFish/KelpPlans.json when build/arcade-development/kelp-plans.request exists. Frozen levels keep
    /// their saved plans; the rest are planned in code (`GameTuning.kelpPlan`).
    @Test func manualWriteKelpPlans() throws {
        let marker = Self.root.appendingPathComponent("build/arcade-development/kelp-plans.request")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let file = Self.root.appendingPathComponent("BiggerFish/KelpPlans.json")
        let existing = (try? JSONDecoder().decode([MeetingPlan].self, from: Data(contentsOf: file))) ?? []
        let plans = GameTuning.kelpSpecs.indices.map { index in
            let spec = GameTuning.kelpSpecs[index]
            return GameTuning.kelpFrozen.contains(spec.name) ? existing.first { $0.spec == spec } ?? GameTuning.kelpPlan(index)
                : GameTuning.kelpPlan(index)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(plans).write(to: file)
    }

    @MainActor @Test func jellyLabFishMeetThePlayerWherePlannedAroundDriftingJellies() {
        // The intro, the first bounce-only meal, and the first fork split by a jelly.
        for index in [0, 4, 5] {
            let plan = GameTuning.jellyLabLevels[index].meetingPlan!
            #expect(!(plan.jellies ?? []).isEmpty)
            let reference = Set(plan.fish.filter(\.referenceMeal).map(\.id))
            let scene = GameScene(world: .jellyBloom, levelIndex: index)
            let actual = scene.debugEncounterCrossings(radii: plan.referenceRadii, eaten: reference)
            for predicted in plan.predicted {
                let real = actual.first { $0.fishID == predicted.fishID }
                #expect(real.map { abs($0.time - predicted.time) < 0.05 && abs($0.y - predicted.y) < 3 } == true,
                        "\(plan.spec.name) fish \(predicted.fishID)")
            }
            if index == 0 {
                // Level 1's demo fish lands on the first jelly you'll pass, while it's ahead of you on screen.
                let demo = plan.jellies!.firstIndex { $0.role == .demo }!
                #expect(plan.jellyPasses.first?.jellyID == demo)
                #expect(scene.debugBounces.contains { bounce in
                    bounce.fishID == plan.jellies![demo].fishID && bounce.jelly == demo
                        && GameTuning.plannerDemoScreen.contains(bounce.screenX / GameTuning.playfieldSize.width)
                })
            }
        }
    }

    @MainActor @Test func plannedLevelsSpawnEveryFishAndKeepPlannedFishOnTheirLine() {
        let scene = GameScene.plannerScene(GameTuning.reefLabSpecs[5])
        let plan = scene.debugMeetingPlan!
        #expect(scene.debugEncounterCrossings(laps: 0.01).isEmpty)
        #expect(scene.debugFishCount == plan.fish.count + 1)
        #expect(scene.debugPlannedFishHoldTheirLine())
    }

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Local-only report on the presets and the shipped campaign, activated by a marker under ignored build/.
    @MainActor @Test func manualMeetingStudy() throws {
        let folder = Self.root.appendingPathComponent("build/arcade-development")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("meeting-study.request").path) else { return }
        var lines: [String] = []
        for spec in GameTuning.reefLabSpecs {
            let started = Date()
            let plan = MeetingPlanner.plan(spec)
            lines.append("## \(spec.name): \(plan.fish.count) fish, seed \(plan.seed), planned in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
            lines.append("issues: \(plan.issues)")
            // Forks are choices only if their lanes exclude each other: the most you can eat on lap one
            // should be every single, every gate, and one lane per fork.
            let designedMost = spec.segments.reduce(0) { $0 + $1.mostMeals + 1 }
            let forkMeals = plan.fish.filter { $0.fork != nil }
            let lanesEaten = Dictionary(grouping: forkMeals.filter { plan.fullestRoute.contains($0.id) }, by: { $0.fork! })
                .mapValues { Set($0.map(\.lane)).count }
            lines.append("most lap-one meals \(plan.analysis.maximumMeals), designed \(designedMost); forks with both lanes on the fullest route: \(lanesEaten.filter { $0.value > 1 }.count) of \(Set(forkMeals.compactMap(\.fork)).count)")
            let actual = GameScene.plannerScene(spec).debugEncounterCrossings(radii: plan.referenceRadii,
                eaten: Set(plan.fish.filter(\.referenceMeal).map(\.id)))
            lines.append(Self.table(plan: plan, actual: actual))
            for policy in ArcadeSimulation.Policy.allCases {
                let result = GameScene.plannerScene(spec).debugSimulate(candidate: spec.name, tuning: ArcadeTuning(level: plan.level),
                    policy: policy, seed: 0, limit: 90)
                lines.append("\nbot \(policy.rawValue): \(result.outcome) in \(String(format: "%.1f", result.seconds)) s, \(result.stats.playerMeals) meals, \(result.reason)")
            }
            // How close each gate and returning threat is for a player who eats everything on lap one.
            let full = plan.radii(eating: plan.fullestRoute)
            func size(at fish: PlannedFish) -> Double {
                let time = plan.predicted.first { $0.fishID == fish.id }!.time
                return Double(fish.radius / full[min(full.count - 1, Int(time / Double(GameTuning.simulationStep)))])
            }
            let gateRatios = plan.fish.filter { $0.role == .gate }.map { String(format: "%.2f", size(at: $0)) }
            let threatRatios = plan.fish.filter { $0.role == .threat }.map { String(format: "%.2f", Double($0.radius / full.last!)) }
            let guardedMeals = plan.analysis.meetings.filter(\.danger).count
            lines.append("\neating everything: gates at \(gateRatios.joined(separator: ", ")) of your size; lap-two fish at \(threatRatios.joined(separator: ", ")) of your end size; danger meals \(guardedMeals)")
            for (route, meals) in [("fewest meals", plan.fewestMealRoute), ("fullest", plan.fullestRoute)] {
                let crossings = GameScene.plannerScene(spec).debugEncounterCrossings(radii: plan.radii(eating: meals), eaten: meals)
                let drift = plan.predicted.compactMap { predicted -> (Int, Double, Double)? in
                    guard let real = crossings.first(where: { $0.fishID == predicted.fishID }) else { return (predicted.fishID, .infinity, .infinity) }
                    return (predicted.fishID, real.time - predicted.time, real.y - predicted.y)
                }
                let worst = drift.max { abs($0.1) < abs($1.1) }
                let analysis = EncounterAnalyzer.analyze(crossings)
                let gates = plan.fish.filter { $0.role == .gate }.map { gate -> String in
                    let m = analysis.meeting(fishID: gate.id)
                    return "gate \(gate.id): meals \(m?.minimumMeals.map(String.init) ?? "–") routes \(m?.routes ?? 0) slack \(m?.robustSlack.map(String.init) ?? "–")"
                }
                lines.append("\n\(route): worst time drift \(worst.map { "fish \($0.0) \(String(format: "%.2f", $0.1)) s" } ?? "–"), " +
                    "worst height drift \(String(format: "%.0f", drift.map { abs($0.2) }.max() ?? 0)) pt, missing \(drift.filter { $0.1.isInfinite }.map(\.0)) · " + gates.joined(separator: " · "))
            }
        }
        try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("meeting-study.md"), atomically: true, encoding: .utf8)
    }

    /// The shipped campaign through the same lens: a ghost run, then a replay eating the fullest route.
    @MainActor @Test func manualCampaignStudy() throws {
        let folder = Self.root.appendingPathComponent("build/arcade-development")
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("campaign-study.request").path) else { return }
        var lines = ["| world | slot | met | max meals | gates (meals/routes/slack) | tightest slack | danger meals | head-on | mean gap s |",
                     "|---|---|---|---|---|---|---|---|---|"]
        var json: [[String: Any]] = []
        for world in ArcadeWorld.campaign {
            for index in world.levels.indices {
                let first = EncounterAnalyzer.analyze(GameScene(world: world, levelIndex: index).debugEncounterCrossings())
                let byID = Dictionary(uniqueKeysWithValues: first.meetings.map { ($0.crossing.fishID, $0.crossing) })
                let meals = first.fullestRoute.compactMap { byID[$0] }.map { (CGFloat($0.distance), CGFloat($0.radius)) }
                let radii = PlayerTimeline.reference(meals: meals, crossSeconds: world.levels[index].screenCrossSeconds,
                    until: GameTuning.playfieldSize.width * GameTuning.worldScreens * 1.05).radius
                let crossings = GameScene(world: world, levelIndex: index)
                    .debugEncounterCrossings(radii: radii, eaten: Set(first.fullestRoute))
                let analysis = EncounterAnalyzer.analyze(crossings)
                // A gate is a fish about your size that only becomes edible after earlier meals.
                let gates = analysis.meetings.filter { ($0.minimumMeals ?? 0) >= 1 && ($0.sizeRatio ?? 0) >= 0.9 }
                let gaps = zip(crossings.dropFirst(), crossings).map { $0.time - $1.time }
                let route = Set(analysis.fullestRoute)
                let danger = analysis.meetings.filter { route.contains($0.crossing.fishID) && $0.danger }.count
                lines.append("| \(world.rawValue) | \(index + 1) | \(crossings.count) | \(analysis.maximumMeals) | " +
                    gates.map { "\($0.minimumMeals!)/\($0.routes)/\($0.robustSlack.map(String.init) ?? "–")" }.joined(separator: ", ") +
                    " | \(gates.compactMap(\.robustSlack).min().map(String.init) ?? "–") | \(danger) | " +
                    String(format: "%.0f%%", 100 * Double(crossings.filter(\.headOn).count) / Double(max(1, crossings.count))) +
                    " | " + String(format: "%.2f", gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)) + " |")
                json.append(["world": world.rawValue, "slot": index + 1,
                             "analysis": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(analysis))) ?? [:]])
            }
        }
        try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("campaign-study.md"), atomically: true, encoding: .utf8)
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("campaign-study.json"))
    }

    static func table(plan: MeetingPlan, actual: [EncounterCrossing]) -> String {
        var rows = ["| id | role | seg | t plan | t real | y plan | y real | size | head-on | min meals | max | routes | slack | ratio | danger |",
                    "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for fish in plan.fish {
            let predicted = plan.predicted.first { $0.fishID == fish.id }
            let real = actual.first { $0.fishID == fish.id }
            let meeting = plan.analysis.meeting(fishID: fish.id)
            func f(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "–" }
            rows.append("| \(fish.id) | \(fish.role.rawValue) | \(fish.segment + 1) | \(f(predicted?.time)) | \(f(real?.time)) | \(f(predicted?.y)) | \(f(real?.y)) | \(f(Double(fish.radius / GameTuning.baseRadius))) | \(fish.headOn) | \(meeting?.minimumMeals.map(String.init) ?? "–") | \(meeting?.maximumMeals.map(String.init) ?? "–") | \(meeting?.routes ?? 0) | \(meeting?.robustSlack.map(String.init) ?? "–") | \(f(meeting?.sizeRatio)) | \(meeting?.danger == true ? "yes" : "") |")
        }
        return rows.joined(separator: "\n")
    }
}
