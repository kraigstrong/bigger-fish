import CoreGraphics
import Testing
@testable import MathReef

struct PromptPlacementTests {
    private typealias L = ReefTuning
    private let height: CGFloat = 402

    /// The fish height where the question, above it, first touches the top clearance.
    private var flipY: CGFloat { height - L.promptTopClearance - L.promptOffset - L.promptPillHeight / 2 }

    @Test func staysAboveUntilItWouldBeCutOff() {
        var placement = PromptPlacement()
        let middle = placement.update(playerY: height / 2, screenHeight: height)
        let atFlip = placement.update(playerY: flipY, screenHeight: height)
        #expect(!middle && !atFlip)
        #expect(!placement.below)
    }

    @Test func movesBelowNearTheTop() {
        var placement = PromptPlacement()
        let changed = placement.update(playerY: flipY + 1, screenHeight: height)
        #expect(changed && placement.below)
    }

    /// Bobbing around the flip point, or dipping a little, doesn't bring it back above.
    @Test func hysteresisKeepsItFromFlailing() {
        var placement = PromptPlacement()
        _ = placement.update(playerY: flipY + 1, screenHeight: height)
        for y in [flipY - 1, flipY + 1, flipY - 20, flipY + 5, flipY - L.promptFlipHysteresis] {
            let changed = placement.update(playerY: y, screenHeight: height)
            #expect(!changed && placement.below)
        }
    }

    @Test func returnsAboveOnceWellClearOfTheTop() {
        var placement = PromptPlacement()
        _ = placement.update(playerY: flipY + 1, screenHeight: height)
        let changed = placement.update(playerY: flipY - L.promptFlipHysteresis - 1, screenHeight: height)
        #expect(changed && !placement.below)
    }

    /// The top of the water must reach the flip point, or the fix never kicks in.
    @Test func theTopOfTheWaterIsInsideTheFlipZone() {
        let playerMaxY = height - L.waterTopMargin - L.playerRadius * 0.95
        #expect(playerMaxY > flipY)
        #expect(playerMaxY - L.promptOffset - L.promptPillHeight / 2 > L.waterBottomMargin)
    }
}
