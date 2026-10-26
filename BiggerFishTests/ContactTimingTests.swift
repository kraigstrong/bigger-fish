import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

/// The planner's timeline starts each swallow when the meal's body really reaches you: later for a fish coming at
/// you than for one standing still at its meeting point, sooner for one you overtake. Gates in new plans are sized
/// for the size you are at contact (Shallow Reef 14's gate 22 was lost by a hair while still growing from the lane
/// meal). Frozen plans keep their old timing.
struct ContactTimingTests {
    private static func swallowStart(_ meal: PlayerTimeline.Meal) -> Int {
        let timeline = PlayerTimeline.reference(meals: [meal], crossSeconds: 2.5, until: 2000)
        return timeline.radius.firstIndex { $0 > GameTuning.baseRadius + 0.01 }!
    }

    @Test func aFishComingAtYouIsTouchedLaterAndOneYouOvertakeSooner() {
        let still = Self.swallowStart(.init(distance: 1000, radius: 12))
        let headOn = Self.swallowStart(.init(distance: 1000, radius: 12, speed: 150, headOn: true))
        let overtaken = Self.swallowStart(.init(distance: 1000, radius: 12, speed: 150, headOn: false))
        #expect(headOn > still && overtaken < still, "\(overtaken) \(still) \(headOn)")
        // About the reach over the closing speed: 29 points at 350 against 500 a second is 0.025 s, a step or two.
        #expect(headOn - still <= 3 && still - overtaken <= 6)
        // The old form is the still fish.
        #expect(PlayerTimeline.reference(meals: [(distance: CGFloat(1000), radius: CGFloat(12))], crossSeconds: 2.5, until: 2000).radius
                == PlayerTimeline.reference(meals: [PlayerTimeline.Meal(distance: 1000, radius: 12)], crossSeconds: 2.5, until: 2000).radius)
    }

    /// In a new plan every gate is edible the moment you touch it on the reference route, grown as far as you are by
    /// then (Riptide Reef's trials, the Open Water's first stages), and none is reported as coming mid-growth.
    @Test func newPlansGatesAreEdibleAtContact() {
        var plans = ArcadeWorld.riptideReef.levels.map { $0.meetingPlan! }
        for seed in UInt64(1)...3 { plans += (0..<5).map { OpenWater.plan($0, seed: seed) } }
        for plan in plans {
            #expect(plan.issues.allSatisfy { !$0.contains("still growing") }, "\(plan.spec.name): \(plan.issues)")
            let timeline = plan.referenceTimeline
            let reference = plan.fish.filter(\.referenceMeal).sorted { $0.meetingDistance < $1.meetingDistance }
            for (order, fish) in reference.enumerated() where fish.role == .gate && order < timeline.contacts.count {
                let you = timeline.radius[timeline.contacts[order]]
                #expect(GameRules.playerEncounter(you, fish.radius) == .firstEatsSecond,
                        "\(plan.spec.name) gate \(fish.id): \(fish.radius) against you at \(you)")
            }
        }
    }

    @Test func frozenPlansKeepTheirTimingAndNewPlansAreContactTimed() {
        for world in ArcadeWorld.campaign {
            for level in world.levels {
                #expect(level.meetingPlan!.contactTimed == nil, "\(level.meetingPlan!.spec.name)")
            }
        }
        for level in ArcadeWorld.riptideReef.levels {
            #expect(level.meetingPlan!.contactTimed == true)
        }
        #expect(OpenWater.plan(0, seed: 1).contactTimed == true)
        #expect(MeetingPlanner.plan(GameTuning.reefLabSpecs[1]).contactTimed == true)
    }
}
