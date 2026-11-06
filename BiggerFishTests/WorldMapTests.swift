import CoreGraphics
import FishKit
import Testing
@testable import BiggerFish

/// The world map squeezed six worlds onto a small phone until their names ran into the bubbles of the row below
/// ("super scrunched"): where the worlds don't fit, it keeps them apart and scrolls sideways, as the level maps do.
struct WorldMapTests {
    /// The room the world map has: every iPhone's in landscape (`ScreenFitTests.phones`), the closed iPhone Duo's past
    /// its camera strip, and an iPad's, which lays the map out at the biggest phone's size (`ScreenScaled`).
    static let phones = ScreenFitTests.phones + [CGSize(width: 594, height: 432)]
    static let screens = phones
        + ScreenFitTests.iPads.map { CGSize(width: $0.width / ScreenFit.menuScale(for: $0), height: $0.height / ScreenFit.menuScale(for: $0)) }

    /// A stop's height on the map: the top row for the first world and every other one after it, the bottom row for
    /// the rest.
    private static func row(_ index: Int, in size: CGSize) -> CGFloat {
        size.height * (index.isMultiple(of: 2) ? GameTuning.worldMapRows.upper : GameTuning.worldMapRows.lower)
    }

    /// However many worlds there are, on every screen: spread across it at least `worldMapTightestSpacing` apart, or
    /// `worldMapSpacing` apart on a map that scrolls, zig-zagging between the two rows, with the same margins at the
    /// map's ends.
    @Test func worldsStayApartOnEveryScreen() {
        for size in Self.screens {
            for count in 1...12 {
                let stops = ArcadeWorldMap.stops(count: count, in: size)
                let spread = OceanMapLayout.worldCenters(count: count, size: size)
                #expect(stops.centers.count == count && stops.width >= size.width, "\(size), \(count) worlds")
                let gaps = zip(stops.centers, stops.centers.dropFirst()).map { $1.x - $0.x }
                #expect(gaps.allSatisfy { $0 >= GameTuning.worldMapTightestSpacing - 1e-9 }, "\(size), \(count) worlds")
                if stops.width > size.width {
                    #expect(gaps.allSatisfy { abs($0 - GameTuning.worldMapSpacing) < 1e-9 }, "\(size), \(count) worlds")
                }
                #expect(stops.centers.indices.allSatisfy { stops.centers[$0].y == Self.row($0, in: size) }, "\(size), \(count) worlds")
                guard count > 1 else { continue }
                #expect(abs(stops.centers[0].x - spread[0].x) < 1e-9, "\(size), \(count) worlds")
                #expect(abs((stops.width - stops.centers[count - 1].x) - (size.width - spread[count - 1].x)) < 1e-9,
                        "\(size), \(count) worlds")
            }
        }
    }

    /// Where the worlds fit, they're spread across the screen as they always were: the campaign's five on every
    /// iPhone but the smallest, and on an iPad with the prototypes too. On an iPhone SE's screen and the closed iPhone
    /// Duo's, the map scrolls.
    @Test func theMapScrollsOnlyWhereTheWorldsDontFit() {
        let campaign = ArcadeWorld.campaign.count, all = ArcadeWorld.mapWorlds(includingPrototypes: true).count
        // An iPhone 16, 17 Pro, Air and Pro Max past their Dynamic Islands, and an iPad.
        let fits = [CGSize(width: 734, height: 372), CGSize(width: 750, height: 381), CGSize(width: 776, height: 399),
                    CGSize(width: 832, height: 419)].map { ($0, campaign) }
            + [(ScreenFit.largestPhone, campaign), (ScreenFit.largestPhone, all)]
        for (size, count) in fits {
            let stops = ArcadeWorldMap.stops(count: count, in: size)
            #expect(stops.width == size.width
                    && stops.centers.map(\.x) == OceanMapLayout.worldCenters(count: count, size: size).map(\.x),
                    "\(size), \(count) worlds")
        }
        // An iPhone SE (and an iPhone Duo running a build from before Xcode 27), and the closed iPhone Duo.
        for size in [CGSize(width: 667, height: 375), CGSize(width: 594, height: 432)] {
            #expect(ArcadeWorldMap.stops(count: campaign, in: size).width > size.width, "\(size)")
        }
    }

    /// On every phone, the shortest (an iPhone 17e's 369) included: your fish over a top-row world stays below Back and
    /// Adventure's name, and the bottom row's names stay above "Swipe to explore." along the bottom. (Math Reef's rows put
    /// the fish against the buttons and the names against the bottom line.)
    @Test func theFishAndTheNamesClearTheMenus() {
        // Back is 44 tall, 10 from the top. The fish (radius 18) reaches about 20 above where it swims and bobs 4 more.
        // A world's name ends 70 below its center, and "Swipe to explore." (12-point type, 12 from the bottom) stands
        // 24 high: its descent 3 and its cap height 9 over that 12. Each keeps a few points' gap.
        let buttonsBottom: CGFloat = 10 + 44, fishTop: CGFloat = 20 + 4, namesBottom: CGFloat = 70, footer: CGFloat = 12 + 3 + 9
        let gap: CGFloat = 4
        for size in Self.phones {
            let stops = ArcadeWorldMap.stops(count: ArcadeWorld.mapWorlds(includingPrototypes: true).count, in: size)
            let top = size.height - stops.centers[0].y, bottom = size.height - stops.centers[1].y
            #expect(top - ArcadeWorldMap.fishLift - fishTop >= buttonsBottom + gap, "\(size)")
            #expect(bottom + namesBottom <= size.height - footer - gap, "\(size)")
        }
    }

    /// The map opens with the world you're on in the middle, or as near as the map's ends allow.
    @Test func theMapOpensOnYourWorld() {
        #expect(ArcadeWorldMap.scrollAnchor(centering: 500, width: 874, screenWidth: 874) == 0)
        #expect(ArcadeWorldMap.scrollAnchor(centering: 106, width: 1000, screenWidth: 600) == 0)
        #expect(ArcadeWorldMap.scrollAnchor(centering: 500, width: 1000, screenWidth: 600) == 0.5)
        #expect(ArcadeWorldMap.scrollAnchor(centering: 894, width: 1000, screenWidth: 600) == 1)
    }
}
