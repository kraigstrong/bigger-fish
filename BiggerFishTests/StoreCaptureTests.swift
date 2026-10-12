import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

/// App Store captures (`StoreCapture`): which moment a launch captures, the progress it stages, and how it judges a
/// frame. The frames themselves are checked by running `scripts/bigger-fish-store-capture.sh` and looking at them.
struct StoreCaptureTests {
    private typealias Swimmer = StoreCapture.Swimmer

    /// Your fish, in the middle of the water at its starting place on screen.
    private let player = Swimmer(id: 0, center: CGPoint(x: 262, y: 201), radius: 20)

    @Test func momentsTellTheGameInTheListingsOrder() throws {
        #expect(StoreCapture.Moment.allCases.map(\.rawValue)
                == ["eat", "dodge", "missed", "jelly-tops", "kelp-shadows", "sunset-hooks", "midnight-light", "conquered",
                    "deep-end"])
        // The script captures the same moments, in the same order.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: root.appendingPathComponent("scripts/bigger-fish-store-capture.sh"), encoding: .utf8)
        let line = try #require(script.split(separator: "\n").first(where: { $0.hasPrefix("MOMENTS=(") }))
        #expect(line.dropFirst("MOMENTS=(".count).dropLast().split(separator: " ").map(String.init)
                == StoreCapture.Moment.allCases.map(\.rawValue))
    }

    @Test func aLaunchCapturesTheMomentItNames() {
        #expect(StoreCapture.moment(in: ["BiggerFish", "-storeCapture", "jelly-tops"]) == .jellyTops)
        #expect(StoreCapture.moment(in: ["BiggerFish", "-arcadeDisableRunRecording", "-storeCapture", "deep-end"]) == .deepEnd)
        #expect(StoreCapture.moment(in: ["BiggerFish"]) == nil)
        #expect(StoreCapture.moment(in: ["BiggerFish", "-storeCapture"]) == nil)
        #expect(StoreCapture.moment(in: ["BiggerFish", "-storeCapture", "jellyTops"]) == nil)
    }

    @Test func eachMomentPlaysAWorldsOwnLevelOrShowsAScreen() throws {
        let worlds: [StoreCapture.Moment: ArcadeWorld] = [.eat: .shallowReef, .dodge: .shallowReef, .missed: .shallowReef,
            .jellyTops: .jellyBloom, .kelpShadows: .kelpForest, .sunsetHooks: .sunsetCove, .midnightLight: .midnightZone]
        for moment in StoreCapture.Moment.allCases {
            if let world = worlds[moment] {
                let level = try #require(moment.level)
                #expect(level.world == world)
                #expect((0..<world.levelCount).contains(level.index))
                #expect(moment.map == nil && !moment.policies.isEmpty)
            } else {
                #expect(moment.level == nil && moment.policies.isEmpty)
            }
        }
        #expect(StoreCapture.Moment.conquered.map == .shallowReef)
    }

    /// Staged progress loads like a real save: Shallow Reef conquered and its Deep End open, nothing else started, and
    /// no tutorial. Only the Deep End's moment has Shallow Reef's "conquered" screen still to show.
    @Test func stagedProgressHasConqueredShallowReef() throws {
        for moment in StoreCapture.Moment.allCases {
            let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
            defaults.set(try JSONEncoder().encode(StoreCapture.stagedSave(for: moment)), forKey: ArcadeProgress.key)
            let progress = ArcadeProgress(defaults: defaults)
            #expect(progress.clearedCounts(in: .shallowReef) == (main: ArcadeWorld.mainLevelCount, deepEnd: 0))
            #expect(progress.isOpen(.shallowReef, ArcadeWorld.mainLevelCount))
            #expect(progress.mapFocus(in: .shallowReef) == ArcadeWorld.mainLevelCount)
            for world in ArcadeWorld.campaign where world != .shallowReef {
                #expect(progress.clearedCounts(in: world) == (main: 0, deepEnd: 0))
            }
            #expect(!progress.needsTutorial && progress.save.hasSeenJellyLesson)
            #expect(progress.unseenUnlock == (moment == .deepEnd ? .shallowReef : nil))
        }
    }

    @Test func eatingIsMidBiteOnAMealYouCanSee() throws {
        func view(shrink: CGFloat?) -> StoreCapture.SceneView {
            var you = player
            var fish = [Swimmer(id: 2, center: CGPoint(x: 500, y: 100), radius: 30),
                        Swimmer(id: 3, center: CGPoint(x: 600, y: 300), radius: 12),
                        Swimmer(id: 4, center: CGPoint(x: 700, y: 200), radius: 10)]
            if let shrink {
                you = Swimmer(id: 0, center: player.center, radius: player.radius, prey: 1)
                fish.append(Swimmer(id: 1, center: CGPoint(x: 285, y: 199), radius: 14, isEaten: true, shrink: shrink))
            }
            return StoreCapture.SceneView(player: you, fish: fish)
        }
        #expect(StoreCapture.score(.eat, view(shrink: 0.6)) != nil)
        // Not eating, or the meal nearly gone.
        #expect(StoreCapture.score(.eat, view(shrink: nil)) == nil)
        #expect(StoreCapture.score(.eat, view(shrink: 0.2)) == nil)
    }

    @Test func dodgingIsABiggerFishJustMissingYou() {
        func score(_ threat: Swimmer) -> Double? {
            StoreCapture.score(.dodge, StoreCapture.SceneView(player: player, fish: [threat]))
        }
        // Twice your size, a little ahead and just under you.
        #expect(score(Swimmer(id: 1, center: CGPoint(x: 300, y: 268), radius: 40)) != nil)
        // Far off, or no bigger than you.
        #expect(score(Swimmer(id: 1, center: CGPoint(x: 700, y: 268), radius: 40)) == nil)
        #expect(score(Swimmer(id: 1, center: CGPoint(x: 300, y: 248), radius: 20)) == nil)
    }

    @Test func aFishThatKeptEatingIsAheadMidBiteAndBigger() {
        func score(at x: CGFloat) -> Double? {
            StoreCapture.score(.missed, StoreCapture.SceneView(player: player, fish: [
                Swimmer(id: 1, center: CGPoint(x: x, y: 200), radius: 30, prey: 2),
                Swimmer(id: 2, center: CGPoint(x: x + 40, y: 200), radius: 10, isEaten: true, shrink: 0.7),
            ]))
        }
        #expect(score(at: 520) != nil)
        #expect(score(at: 100) == nil)
    }

    @Test func aJellyTopIsJustBouncedOff() {
        func score(bounced: CGFloat?) -> Double? {
            StoreCapture.score(.jellyTops, StoreCapture.SceneView(time: 5, player: player,
                jellies: [CGPoint(x: 262, y: 150)], jellyRadius: 40, lastBounce: bounced))
        }
        #expect(score(bounced: 4.95) != nil)
        #expect(score(bounced: nil) == nil)
        #expect(score(bounced: 4) == nil)
    }

    @Test func kelpShadowsAreFishGoneDarkAhead() {
        func score(shade: CGFloat) -> Double? {
            StoreCapture.score(.kelpShadows, StoreCapture.SceneView(player: player,
                fish: [Swimmer(id: 1, center: CGPoint(x: 600, y: 200), radius: 20, shade: shade)]))
        }
        #expect(score(shade: 1) != nil)
        #expect(score(shade: 0) == nil)
    }

    @Test func sunsetHooksHangAheadUnderTheirBoat() {
        let around = [Swimmer(id: 1, center: CGPoint(x: 450, y: 90), radius: 12),
                      Swimmer(id: 2, center: CGPoint(x: 700, y: 300), radius: 25)]
        func score(bait: CGPoint, rodX: CGFloat = 600) -> Double? {
            StoreCapture.score(.sunsetHooks, StoreCapture.SceneView(player: player, fish: around,
                hooks: [StoreCapture.Hook(bait: bait, rodX: rodX)]))
        }
        #expect(score(bait: CGPoint(x: 520, y: 200)) != nil)
        // Behind you, or right at the surface.
        #expect(score(bait: CGPoint(x: 200, y: 200)) == nil)
        #expect(score(bait: CGPoint(x: 520, y: 380)) == nil)
        // Its boat off the edge of the screen.
        #expect(score(bait: CGPoint(x: 520, y: 200), rodX: 900) == nil)
        #expect(StoreCapture.score(.sunsetHooks, StoreCapture.SceneView(player: player, fish: around)) == nil)
    }

    @Test func midnightLightIsAFishInYourBeam() {
        let around = [Swimmer(id: 2, center: CGPoint(x: 400, y: 80), radius: 10),
                      Swimmer(id: 3, center: CGPoint(x: 700, y: 330), radius: 10)]
        func score(_ fish: Swimmer) -> Double? {
            StoreCapture.score(.midnightLight, StoreCapture.SceneView(player: player, fish: around + [fish]))
        }
        #expect(score(Swimmer(id: 1, center: CGPoint(x: 500, y: 201), radius: 15)) != nil)
        #expect(score(Swimmer(id: 1, center: CGPoint(x: 100, y: 201), radius: 15)) == nil)
        // Climbing fast turns the beam up and away from a fish straight ahead.
        let ahead = Swimmer(id: 1, center: CGPoint(x: 500, y: 201), radius: 15)
        let tilt = StoreCapture.headlampTilt(rising: GameTuning.motion.maxRiseSpeed * 2)
        #expect(tilt == GameTuning.headlampMaxTilt)
        #expect(StoreCapture.isLit(ahead, by: player, tilt: 0, width: 874))
        #expect(!StoreCapture.isLit(ahead, by: player, tilt: tilt, width: 874))
    }

    @Test func fishCutOffByAnEdgeCountAgainstAFrame() throws {
        let fish = [Swimmer(id: 1, center: CGPoint(x: 600, y: 200), radius: 20, shade: 1)]
        let clean = try #require(StoreCapture.score(.kelpShadows, StoreCapture.SceneView(player: player, fish: fish)))
        let cut = Swimmer(id: 2, center: CGPoint(x: 870, y: 100), radius: 20)
        let edged = try #require(StoreCapture.score(.kelpShadows, StoreCapture.SceneView(player: player, fish: fish + [cut])))
        #expect(edged < clean)
    }

    @Test func theBestFrameIsntOneJustBeforeYouAreEaten() {
        let takes = [StoreCapture.Take(policy: .collector, step: 100, score: 5),
                     StoreCapture.Take(policy: .collector, step: 500, score: 9)]
        #expect(StoreCapture.best(takes, eatenAt: nil)?.step == 500)
        #expect(StoreCapture.best(takes, eatenAt: 500 + StoreCapture.lastStepsBeforeEaten)?.step == 100)
        #expect(StoreCapture.best(takes, eatenAt: 150) == nil)
    }
}
