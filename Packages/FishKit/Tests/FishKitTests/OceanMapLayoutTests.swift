import CoreGraphics
import Testing
@testable import FishKit

struct OceanMapLayoutTests {
    @Test func worldLayoutPreservesMathReefsPositions() {
        let size = CGSize(width: 874, height: 402)
        let stops = OceanMapLayout.worldCenters(count: 5, size: size)
        #expect(stops.count == 5)
        #expect(stops.first == CGPoint(x: 106, y: size.height * 0.60))
        #expect(stops.last == CGPoint(x: 718, y: size.height * 0.60))
        #expect(stops[1].y == size.height * 0.38)
        #expect(OceanMapLayout.worldCenters(count: 0, size: size).isEmpty)
        #expect(OceanMapLayout.worldCenters(count: 1, size: size).first?.x == size.width / 2)
    }

    @Test func expandingTheCampaignPreservesEarlierStopsAndTrailingMargin() {
        let short = OceanMapLayout.levelCenters(count: 10, height: 402)
        let long = OceanMapLayout.levelCenters(count: 100, height: 402)
        #expect(Array(long.prefix(10)) == short)
        #expect(long[99].x + 110 == OceanMapLayout.levelContentWidth(count: 100))
        #expect(long.allSatisfy { $0.y >= 402 * 0.28 && $0.y <= 402 * 0.60 })
    }
}
