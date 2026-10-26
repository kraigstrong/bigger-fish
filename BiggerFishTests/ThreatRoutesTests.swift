import CoreGraphics
import Foundation
import Testing
@testable import BiggerFish

/// The analyzer's reach check reckons with bigger fish crossing between two meals (`ThreatRoutes`): the wall report
/// found the reach check's blind spot on Sunset Cove 12 (a gate whose meals nobody could dive to between two big fish)
/// and Shallow Reef 3 (a danger fish guarding one meal sitting in the climb to the next).
struct ThreatRoutesTests {
    private static func crossing(_ id: Int, at time: Double, y: Double, radius: Double, headOn: Bool = true, speed: Double = 120) -> EncounterCrossing {
        EncounterCrossing(fishID: id, time: time, distance: time * 350, y: y, radius: radius, headOn: headOn, zoom: 1, speed: speed)
    }

    @Test func aBiggerFishCrossingBetweenTwoMealsHasToBePassedAboveOrBelow() {
        // Two meals 1.2 s apart, from mid-water to a little higher: easy, until a giant crosses on top of the line
        // between them with no room over it and too little time to dive under it and climb back.
        let meals = [Self.crossing(1, at: 2, y: 200, radius: 10), Self.crossing(3, at: 3.2, y: 260, radius: 10)]
        #expect(EncounterAnalyzer.analyze(meals).meeting(fishID: 3)?.maximumMeals == 1)
        let giant = Self.crossing(2, at: 3.15, y: 300, radius: 90)
        let blocked = EncounterAnalyzer.analyze(meals + [giant])
        #expect(blocked.meeting(fishID: 3)?.minimumMeals == nil)
        // The same giant crossing a second earlier leaves time to come back up after it.
        let early = Self.crossing(2, at: 2.3, y: 300, radius: 90)
        #expect(EncounterAnalyzer.analyze(meals + [early]).meeting(fishID: 3)?.maximumMeals == 1)
        // Two big fish a third of a second apart, one high and one low, with the meal between them: nothing to dive between.
        let high = Self.crossing(2, at: 2.7, y: 330, radius: 50), low = Self.crossing(4, at: 3.0, y: 120, radius: 50)
        let squeezed = EncounterAnalyzer.analyze(meals + [high, low])
        #expect(squeezed.meeting(fishID: 3)?.maximumMeals == 1)
        // A fish swimming your way is alongside you for longer than one coming at you.
        let overtaken = Self.crossing(2, at: 2.5, y: 300, radius: 90, headOn: false, speed: 250)
        #expect(EncounterAnalyzer.analyze(meals + [overtaken]).meeting(fishID: 3)?.minimumMeals == nil)
    }

    /// Sunset Cove 12 as shipped: gate 16 (30.9) opens after six meals. At its planned 32.2 the planner counted on a
    /// seventh up top (11 or 13), and the way down from 13 ends between threats 14 and 15: Kraig's 42 runs and his
    /// tester's never got through, and #193 shrank the gate. The check closes the way down from 13; the way down from 11
    /// survives it by a hair (a full-speed dive from the bottom of 11's reach, under 14 as its body tapers away), which
    /// is as close as the planner's optimistic steering can call it.
    @Test func sunsetCove12sOldGateHadNoWayDownFrom13() {
        let plan = ArcadeWorld.sunsetCove.level(11).meetingPlan!
        let speeds = Dictionary(uniqueKeysWithValues: plan.fish.map { ($0.id, Double($0.cruiseSpeed)) })
        func analysis(gate: Double, without: Set<Int> = []) -> EncounterAnalysis {
            EncounterAnalyzer.analyze(plan.predicted.filter { !without.contains($0.fishID) }.map { c in
                EncounterCrossing(fishID: c.fishID, time: c.time, distance: c.distance, y: c.y, radius: c.fishID == 16 ? gate : c.radius,
                                  headOn: c.headOn, zoom: c.zoom, speed: speeds[c.fishID])
            })
        }
        #expect(plan.fish[15].role == .gate && plan.fish[15].radius == 30.9)
        let shipped = analysis(gate: 30.9).meeting(fishID: 16)
        #expect(shipped?.minimumMeals == 6 && shipped?.fewestRoute == [1, 2, 3, 7, 9, 11, 16], "\(String(describing: shipped))")
        // With the top lane's 11 and the low 12 out of it, the only seventh meal is 13, and from there the old gate is
        // out of reach: the fewest-meal route needs more than the six the planner designed, or doesn't exist.
        let top = analysis(gate: 32.2, without: [11, 12]).meeting(fishID: 16)
        #expect((top?.minimumMeals ?? 99) > 6, "\(String(describing: top))")
        // Without the threats between, 13 would do.
        let open = analysis(gate: 32.2, without: [11, 12, 14, 15]).meeting(fishID: 16)
        #expect(open?.minimumMeals == 6, "\(String(describing: open))")
    }
}
