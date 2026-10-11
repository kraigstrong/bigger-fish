import Foundation
import Testing
@testable import BiggerFish

/// A frozen level plays exactly as it was played and approved. Each one's fingerprint is pinned below, so changing a
/// frozen level (its fish, jellies, kelp, seed, or settings) means editing its line here: never a side effect of a
/// planner change or a regenerated plans file. To change one on purpose (with Kraig's OK), unfreeze it, tune it, freeze
/// it again, and update its line with the fingerprint this test prints.
struct FrozenLevelTests {
    /// What a level plays. The planner's predictions and analysis (also saved) don't change play, so they're left out.
    private struct Played: Encodable {
        let spec: MeetingSpec
        let seed: UInt64
        let fish: [PlannedFish]
        let jellies: [PlannedJelly]?
        let kelp: [PlannedKelp]?
    }

    private static func fingerprint(_ plan: MeetingPlan) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Played(spec: plan.spec, seed: plan.seed, fish: plan.fish, jellies: plan.jellies, kelp: plan.kelp))
        // FNV-1a, 64 bits: stable from run to run, unlike `Hasher`.
        let hash = data.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
        return String(hash, radix: 16)
    }

    private static let worlds: [(file: String, frozen: Set<String>)] = [
        ("ReefLabPlans", GameTuning.reefLabFrozen), ("JellyLabPlans", GameTuning.jellyLabFrozen),
        ("KelpPlans", GameTuning.kelpFrozen), ("MidnightPlans", GameTuning.midnightFrozen),
    ]

    @Test(arguments: worlds.map(\.file)) func frozenLevelsAreExactlyAsPlayed(_ file: String) throws {
        let frozen = try #require(Self.worlds.first { $0.file == file }).frozen
        let saved = GameTuning.savedPlans(file)
        for plan in saved where frozen.contains(plan.spec.name) {
            let fingerprint = try Self.fingerprint(plan)
            #expect(Self.played[plan.spec.name] == fingerprint, "\"\(plan.spec.name)\": \"\(fingerprint)\",")
        }
        // Every frozen level is pinned, and only frozen ones: freezing or unfreezing a level edits this table too.
        let names = Set(saved.map(\.spec.name))
        #expect(frozen.isSubset(of: names), "\(file) is missing frozen levels: \(frozen.subtracting(names).sorted())")
        let pinned = Set(Self.played.keys).intersection(names)
        #expect(pinned == frozen, "pinned but not frozen: \(pinned.subtracting(frozen).sorted())")
    }

    /// Every frozen level's fingerprint, by level name.
    private static let played: [String: String] = [
        // Shallow Reef, by layout (`GameTuning.shallowReefOrder` sets which slot plays each)
        "Reef Lab 1": "26c9e2d0eb70eb40",
        "Easy": "b9dbadd9f6122339",
        "Reef Lab 3": "8906fd6793e6590a",
        "Reef Lab 4": "9003658a4bba540a",
        "Reef Lab 5": "e44c9b313a8a6856",
        "Medium": "c2ab62332e11bb1b",
        "Reef Lab 7": "43de0ecb9428cb4d",
        "Reef Lab 8": "6bf74a4660098de1",
        "Reef Lab 9": "1927f99ebbb15313",
        "Hard": "7e1d634959d0408a",
        "Crossroads": "9bbd303f147d46e5",
        "Frenzy": "ba2213c33929675e",
        "Gauntlet": "477a68ea4d9bd256",
        "Heavyweights": "4845c703f27ee473",
        "Needle": "3f2cbce5713e49bd",
        // Jelly Bloom
        "Jelly Lab 1": "db4568267aefdd68",
        "Jelly Lab 2": "96e5454176378e8d",
        "Jelly Lab 3": "ca8acec063b4227b",
        "Jelly Lab 4": "65f2f46e3122dcd2",
        "Jelly Lab 5": "9be0ec69041809d1",
        "Jelly Lab 6": "241df64bb82222ff",
        "Jelly Lab 7": "f683b695a49f1366",
        "Jelly Lab 8": "b5e293f67963f067",
        "Jelly Lab 9": "59fd2bfbb35d5f42",
        "Jelly Lab 10": "c68339a63a204495",
        "Bell Field": "4cf395e351dd467d",
        "Jelly Frenzy": "b8902d543b155e21",
        "Jelly Gauntlet": "3f57fa81984f8cb9",
        "Night Heavyweights": "26f063d23429d48f",
        "Curtain": "6ae838107cfaaacc",
        // Kelp Forest
        "Kelp Forest 1": "dd6ae14abee829f0",
        "Kelp Forest 2": "2a4eb92cb3b872c7",
        "Kelp Forest 3": "c3e9617273c04d73",
        "Kelp Forest 4": "1ba998aa0bc75746",
        "Kelp Forest 5": "8e02ebc8eca65ad2",
        "Kelp Forest 6": "8d831675f4c7ee09",
        "Kelp Forest 7": "6ccc7a9e1c0cb2da",
        "Kelp Forest 8": "e8708e393770c963",
        "Kelp Forest 9": "7b2b9a9f914e62e",
        "Kelp Forest 10": "599672e0d0c8cfc3",
        "Kelp Forest 11": "a97b488d8319dc1f",
        "Kelp Forest 12": "5d003343df07c642",
        "Kelp Forest 13": "19774d013b323698",
        "Kelp Forest 14": "88036116efeb3101",
        "Kelp Forest 15": "df928b4d2153f73d",
        // Midnight Zone
        "Midnight Zone 1": "648ee3c791a9b336",
        "Midnight Zone 2": "f6d9314abc6f2ac6",
        "Midnight Zone 3": "ce709dc80d585e8c",
        "Midnight Zone 4": "d115b44b226e7814",
        "Midnight Zone 5": "c8a0f81783570b02",
        "Midnight Zone 6": "5a377e2c7d684f5e",
        "Midnight Zone 7": "96411bb7af9b441",
        "Midnight Zone 8": "f9713c31c8d6109",
        "Midnight Zone 9": "f57cc261009da889",
        "Midnight Zone 10": "9b6d1a507726fbda",
        "Midnight Zone 11": "49b2488ba600c490",
        "Midnight Zone 12": "17490b1eda2ca618",
        "Midnight Zone 13": "3f6a104135606a6f",
        "Midnight Zone 14": "393f872ce83f9b0f",
        "Midnight Zone 15": "63f26e76171a3890",
    ]
}
