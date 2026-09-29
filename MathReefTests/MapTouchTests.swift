import CoreGraphics
import SpriteKit
import Testing
@testable import MathReef

/// Taps and drags on the reef map and a world's level path, in scene coordinates.
@MainActor
struct MapTouchTests {
    private let size = CGSize(width: 874, height: 402)

    /// Ten levels: the first three open, the rest locked.
    private func levelMap(focus: Int = 0) -> (LevelMapNode, selected: () -> [Int], backs: () -> Int) {
        final class Log { var selected: [Int] = []; var backs = 0 }
        let log = Log()
        let stops = (0..<10).map { i in
            LevelStop(number: i + 1, title: "Level \(i + 1)", stars: 0, state: i < 3 ? .open : .locked, isCheckpoint: false)
        }
        let map = LevelMapNode(size: size, title: "Test", color: .blue, levels: stops, stars: (0, 30), crown: .none, focus: focus)
        map.onSelect = { log.selected.append($0) }
        map.onBack = { log.backs += 1 }
        return (map, { log.selected }, { log.backs })
    }

    private func tap(_ map: LevelMapNode, at point: CGPoint) {
        map.touchBegan(at: point)
        map.touchEnded(at: point)
    }

    @Test func tappingAnOpenLevelSelectsIt() {
        let (map, selected, _) = levelMap()
        tap(map, at: map.screenPoint(ofLevel: 1))
        #expect(selected() == [1])
    }

    @Test func tappingALockedLevelDoesNothing() {
        let (map, selected, _) = levelMap()
        tap(map, at: map.screenPoint(ofLevel: 4))
        #expect(selected().isEmpty)
    }

    @Test func aSmallWobbleStillCountsAsATap() {
        let (map, selected, _) = levelMap()
        let point = map.screenPoint(ofLevel: 2)
        map.touchBegan(at: point)
        map.touchMoved(to: CGPoint(x: point.x - 6, y: point.y))
        map.touchEnded(at: CGPoint(x: point.x - 6, y: point.y))
        #expect(selected() == [2])
    }

    @Test func draggingScrollsWithoutSelecting() {
        let (map, selected, _) = levelMap()
        let start = map.screenPoint(ofLevel: 1)
        map.touchBegan(at: start)
        map.touchMoved(to: CGPoint(x: start.x - 40, y: start.y))
        map.touchMoved(to: CGPoint(x: start.x - 200, y: start.y))
        map.touchEnded(at: CGPoint(x: start.x - 200, y: start.y))
        #expect(selected().isEmpty)
        #expect(map.scrollOffset < 0)
    }

    @Test func scrollingStopsAtBothEnds() {
        let (map, _, _) = levelMap()
        map.touchBegan(at: CGPoint(x: 100, y: 200))
        map.touchMoved(to: CGPoint(x: 600, y: 200))  // past the start
        #expect(map.scrollOffset == 0)
        map.touchMoved(to: CGPoint(x: -5000, y: 200))  // past the end
        let lastLevel = map.screenPoint(ofLevel: 9)
        #expect(lastLevel.x > 0 && lastLevel.x < size.width)
    }

    @Test func theBackButtonGoesBack() {
        let (map, selected, backs) = levelMap()
        tap(map, at: CGPoint(x: 46, y: size.height - 36))
        #expect(backs() == 1)
        #expect(selected().isEmpty)
    }

    @Test func aLaterLevelOpensScrolledIntoView() {
        let (map, _, _) = levelMap(focus: 8)
        let focused = map.screenPoint(ofLevel: 8)
        #expect(focused.x > 0 && focused.x < size.width)
    }

    @Test func theReefMapSelectsPlayableWorldsOnly() {
        var selected: [Int] = []
        let worlds = ["Addition", "Subtraction", "Fractions"].enumerated().map { i, title in
            WorldStop(title: title, symbol: "+", color: .red, stars: 0, maxStars: 3, crown: .none, comingSoon: i == 2)
        }
        let map = WorldMapNode(size: size, worlds: worlds, focus: 0, fishCrown: .none)
        map.onSelect = { selected.append($0) }
        map.handleTap(at: map.screenPoint(ofWorld: 1))
        map.handleTap(at: map.screenPoint(ofWorld: 2))  // coming soon
        map.handleTap(at: CGPoint(x: size.width / 2, y: 20))  // open water
        #expect(selected == [1])
    }
}
