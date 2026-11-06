import CoreGraphics
import Testing
@testable import BiggerFish

/// Trailer footage (`StoreFootage`): which launches record, and what. The footage itself is checked by running
/// `scripts/bigger-fish-footage.sh` and watching it.
struct StoreFootageTests {
    private let level = ["BiggerFish", "-arcadePlaytest", "sunset-cove.10"]

    @Test func aLaunchRecordsALevelWithABot() {
        #expect(StoreFootage.request(in: level + ["-storeFootage", "collector"]) == .init(policy: .collector))
        // It needs a level that exists, and a bot it knows.
        #expect(StoreFootage.request(in: ["BiggerFish", "-storeFootage", "collector"]) == nil)
        #expect(StoreFootage.request(in: ["BiggerFish", "-arcadePlaytest", "shallow-reef.99", "-storeFootage", "collector"]) == nil)
        #expect(StoreFootage.request(in: ["BiggerFish", "-arcadePlaytest", "deep-sea.1", "-storeFootage", "collector"]) == nil)
        #expect(StoreFootage.request(in: level + ["-storeFootage", "greedy"]) == nil)
        #expect(StoreFootage.request(in: level) == nil)
    }

    /// An Open Water run records as a level does, from its seed.
    @Test func anOpenWaterRunRecordsToo() {
        #expect(StoreFootage.request(in: ["BiggerFish", "-openWater", "1003", "-storeFootage", "collector",
                                          "-storeFootageFrom", "10.5", "-storeFootageTo", "15.5"])
                == .init(policy: .collector, from: 10.5, to: 15.5))
    }

    /// Footage can end on the run's result card, for showing a new best.
    @Test func footageCanEndOnTheResultCard() {
        #expect(StoreFootage.request(in: ["BiggerFish", "-openWater", "1003", "-storeFootage", "collector", "-storeFootageCard"])
                == .init(policy: .collector, card: true))
        #expect(StoreFootage.request(in: level + ["-storeFootage", "collector"])?.card == false)
    }

    /// Your fish hatches plain in the footage unless a look is asked for: the shop's items, one of each kind.
    @Test func aLookDressesYourFish() {
        #expect(StoreFootage.look(in: level).isEmpty)
        #expect(StoreFootage.look(in: level + ["-storeFootageLook", "color.galaxy,hat.party,hat.nonsense,trail.confetti"])
                == ["color": "color.galaxy", "hat": "hat.party", "trail": "trail.confetti"])
    }

    @Test func optionsPickTheSecondsEveryNthFrameAndTheSize() {
        let base = level + ["-storeFootage", "cautious"]
        #expect(StoreFootage.request(in: base + ["-storeFootageFrom", "2.5", "-storeFootageTo", "9",
                                                 "-storeFootageEvery", "30", "-storeFootageScale", "0.25"])
                == .init(policy: .cautious, from: 2.5, to: 9, every: 30, scale: 0.25))
        // Frames up to three times the screen, for App Store art.
        #expect(StoreFootage.request(in: base + ["-storeFootageScale", "2.45"]) == .init(policy: .cautious, scale: 2.45))
        // Nonsense is left out: an end before the start, no frames at all, or frames too big to draw.
        #expect(StoreFootage.request(in: base + ["-storeFootageFrom", "5", "-storeFootageTo", "3",
                                                 "-storeFootageEvery", "0", "-storeFootageScale", "4"])
                == .init(policy: .cautious, from: 5))
    }
}
