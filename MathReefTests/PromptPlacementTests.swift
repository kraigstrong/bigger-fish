import CoreGraphics
import Testing
@testable import MathReef

struct PromptPlacementTests {
    private typealias L = ReefTuning
    private let height: CGFloat = 402
    private var reach: CGFloat { L.promptOffset + L.promptPillHeight / 2 }
    /// Above the fish, the question first gets too close to the top past this height.
    private var topFlipY: CGFloat { height - L.promptEdgeClearance - reach }
    /// Below the fish, the question first gets too close to the bottom under this height.
    private var bottomFlipY: CGFloat { L.promptEdgeClearance + reach }

    @Test func staysAboveUntilItWouldBeCutOff() {
        var placement = PromptPlacement()
        let middle = placement.update(playerY: height / 2, screenHeight: height)
        let low = placement.update(playerY: bottomFlipY - 10, screenHeight: height)
        let atFlip = placement.update(playerY: topFlipY, screenHeight: height)
        #expect(!middle && !low && !atFlip && !placement.below)
    }

    @Test func movesBelowNearTheTop() {
        var placement = PromptPlacement()
        let changed = placement.update(playerY: topFlipY + 1, screenHeight: height)
        #expect(changed && placement.below)
    }

    /// Once below, it stays below all the way down, however the fish bobs.
    @Test func staysBelowUntilItWouldBeCutOffAtTheBottom() {
        var placement = PromptPlacement()
        _ = placement.update(playerY: topFlipY + 1, screenHeight: height)
        for y in [topFlipY - 1, topFlipY + 1, height / 2, topFlipY, bottomFlipY] {
            let changed = placement.update(playerY: y, screenHeight: height)
            #expect(!changed && placement.below)
        }
    }

    @Test func returnsAboveNearTheBottom() {
        var placement = PromptPlacement()
        _ = placement.update(playerY: topFlipY + 1, screenHeight: height)
        let changed = placement.update(playerY: bottomFlipY - 1, screenHeight: height)
        #expect(changed && !placement.below)
    }

    /// The fish must be able to reach both switch points, or the question could get stuck cut off.
    @Test func theWaterReachesBothSwitchPoints() {
        let playerMaxY = height - L.waterTopMargin - L.playerRadius * 0.95
        let playerMinY = L.waterBottomMargin + L.playerRadius * 0.95
        #expect(playerMaxY > topFlipY)
        #expect(playerMinY < bottomFlipY)
    }
}
