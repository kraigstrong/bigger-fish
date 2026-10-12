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

    @Test func optionsPickTheSecondsEveryNthFrameAndTheSize() {
        let base = level + ["-storeFootage", "cautious"]
        #expect(StoreFootage.request(in: base + ["-storeFootageFrom", "2.5", "-storeFootageTo", "9",
                                                 "-storeFootageEvery", "30", "-storeFootageScale", "0.25"])
                == .init(policy: .cautious, from: 2.5, to: 9, every: 30, scale: 0.25))
        // Nonsense is left out: an end before the start, no frames at all, or frames bigger than the screen.
        #expect(StoreFootage.request(in: base + ["-storeFootageFrom", "5", "-storeFootageTo", "3",
                                                 "-storeFootageEvery", "0", "-storeFootageScale", "2"])
                == .init(policy: .cautious, from: 5))
    }
}
