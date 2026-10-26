import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

/// The wall report's measure from the plan alone (`MeetingPlan.plannedOpening`), for the pickers that take the first
/// clean layout: a layout whose own route can't be swum is passed by, as a wall of giants is.
struct PlannedOpeningTests {
    /// Riptide Reef 3's first layout, the wall Kraig couldn't get through, reads tighter from the plan than the shipped
    /// layout 4 (he called 7% a wall; by the old measure Heavyweights is 5.7% and a favorite, so the number alone doesn't
    /// decide, and `wallOpening` is his knob). The searching planner's levels (Shallow Reef, Jelly Bloom) have no
    /// plan-side measure: their fish swim freely from the start.
    @Test func riptideReef3sFirstLayoutReadsTighterFromThePlan() throws {
        let spec = GameTuning.riptideSpecs[2]
        let first = try #require(MeetingPlanner.kelpPlan(spec, variation: 0).plannedOpening()?.tightest)
        let shipped = try #require(MeetingPlanner.kelpPlan(spec, variation: 4).plannedOpening()?.tightest)
        #expect(first.share < 0.08 && first.share < shipped.share, "\(first.share) vs \(shipped.share)")
        print("[PlannedOpening] Riptide Reef 3: layout 0 \(Int(first.share * 100))%, layout 4 \(Int(shipped.share * 100))%")
        #expect(ArcadeWorld.shallowReef.level(0).meetingPlan!.plannedOpening() == nil)
        #expect(!ArcadeWorld.shallowReef.level(13).meetingPlan!.hasWall)
    }

    /// Kelp Forest 13's first layout (a wall of giants) reads as a wall from the plan too, and the shipped layouts of
    /// every planned-just-in-time world don't, so nothing frozen would change.
    @Test func shippedLayoutsHaveNoWallFromThePlan() {
        #expect(MeetingPlanner.kelpPlan(GameTuning.kelpSpecs[12], variation: 0).hasWall)
        for world in [ArcadeWorld.kelpForest, .midnightZone, .sunsetCove, .riptideReef] {
            for (index, level) in world.levels.enumerated() {
                let plan = level.meetingPlan!
                #expect(plan.plannedOpening() != nil, "\(world) \(index + 1)")
                #expect(!plan.hasWall, "\(world) \(index + 1): \(String(describing: plan.plannedOpening()?.closed?.reason))")
            }
        }
    }

    /// The measure takes milliseconds, so a run can try many layouts.
    @Test func plannedOpeningIsQuick() {
        let plan = ArcadeWorld.sunsetCove.level(9).meetingPlan!
        let started = Date()
        for _ in 0..<5 { _ = plan.plannedOpening() }
        let each = Date().timeIntervalSince(started) / 5
        #expect(each < 0.25, "\(each) s")
        print("[PlannedOpening] Sunset Cove 10: \(Int(each * 1000)) ms")
    }
}
