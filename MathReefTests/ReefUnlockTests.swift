import Foundation
import Testing
@testable import MathReef

/// The free sample. The purchase itself (`ReefPurchases`) is StoreKit and is checked by hand in
/// Xcode against `MathReef.storekit`: StoreKit test sessions can't run from `xcodebuild test`, where
/// they fail to load and reading entitlements hangs.
struct FreeSampleTests {
    private func world(_ id: String) -> World { Curriculum.worlds.first { $0.id == id }! }

    @Test func threeFreeLevelsPerWorldAndOneInExponents() {
        for world in Curriculum.worlds {
            let expected = world.id == "exponents" ? 1 : 3
            #expect(FreeSample.freeLevels(in: world) == expected, "\(world.id)")
            #expect(world.levels.indices.filter { FreeSample.isFree($0, in: world) }.count == expected, "\(world.id)")
        }
    }

    @Test func everythingPastTheFreeLineNeedsTheUnlock() {
        for world in Curriculum.worlds {
            for index in world.levels.indices {
                let free = FreeSample.isFree(index, in: world)
                #expect(FreeSample.needsUnlock(index, in: world, isUnlocked: false) == !free, "\(world.levels[index].id)")
                #expect(!FreeSample.needsUnlock(index, in: world, isUnlocked: true), "\(world.levels[index].id)")
            }
        }
    }

    /// A skip test past the free line can't be used to get around the unlock, even though skip tests
    /// are otherwise always playable.
    @Test func skipTestsPastTheFreeLineNeedTheUnlock() {
        let checkpoints = Curriculum.worlds.flatMap { world in
            world.levels.indices.filter { world.levels[$0].isCheckpoint }.map { (world, $0) }
        }
        #expect(!checkpoints.isEmpty)
        for (world, index) in checkpoints {
            #expect(!FreeSample.isFree(index, in: world), "\(world.levels[index].id) is a free checkpoint")
            #expect(FreeSample.needsUnlock(index, in: world, isUnlocked: false))
        }
    }

    @Test func theFreeLevelsAreTheEasyStart() {
        #expect(world("addition").levels.prefix(3).map(\.id) == ["add.plus12", "add.make10", "add.doubles"])
        #expect(world("exponents").levels.prefix(1).map(\.id) == ["exp.1"])
    }
}
