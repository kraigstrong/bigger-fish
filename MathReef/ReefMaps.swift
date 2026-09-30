import FishKit
import SpriteKit
import UIKit

// The two map screens: the reef (pick a world) and a world's winding level path. Each is a
// self-contained node built from progress data; the scene forwards touches and time to it.

struct WorldStop {
    let title: String
    let symbol: String
    let color: SKColor
    let stars: Int
    let maxStars: Int
    let crown: Crown
    let comingSoon: Bool
}

enum LevelStopState {
    case locked, open, passed, skipTest
    /// Past the free sample and not yet unlocked: tapping asks for the unlock.
    case needsUnlock
}

struct LevelStop {
    let number: Int
    let title: String
    let stars: Int
    let state: LevelStopState
    let isCheckpoint: Bool
}

/// The reef: every world as a coral stop along a dotted trail.
final class WorldMapNode: SKNode {
    var onSelect: ((Int) -> Void)?

    private var centers: [CGPoint] = []
    private var playable: [Bool] = []
    private let fish = FishNode(style: .player, isPlayer: true, tailPhase: 0)
    private var fishHome = CGPoint.zero

    /// `fishCrown` is the focused world's crown, since the fish waits beside that world.
    init(size: CGSize, worlds: [WorldStop], focus: Int, fishCrown crown: Crown) {
        super.init()
        fish.setHeadwear(fishCrown(crown))
        let bed = seabed(size: size)
        bed.zPosition = -2
        addChild(bed)

        let title = reefLabel("Math Reef", fontSize: 30, heavy: true)
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: 40, y: size.height - 38)
        addChild(title)

        // Clear of the Dynamic Island on either side (its landscape safe-area inset, the largest of any
        // iPhone): the first stop's circle on the left, and on the right the fish, which sits 66
        // past the last stop with its nose about 24 further.
        let count = worlds.count
        let edge: CGFloat = 62
        let left = edge + 44, right = size.width - edge - 94
        centers = worlds.indices.map { i in
            CGPoint(
                x: count > 1 ? left + (right - left) * CGFloat(i) / CGFloat(count - 1) : size.width / 2,
                y: size.height * (i.isMultiple(of: 2) ? 0.60 : 0.38)
            )
        }
        playable = worlds.map { !$0.comingSoon }

        let trail = dottedPath(through: centers)
        trail.zPosition = -1
        addChild(trail)

        for (world, center) in zip(worlds, centers) {
            let stop = SKNode()
            stop.position = center
            stop.alpha = world.comingSoon ? 0.5 : 1

            let circle = SKShapeNode(circleOfRadius: 40)
            circle.fillColor = world.color
            circle.strokeColor = .white
            circle.lineWidth = 4
            stop.addChild(circle)
            let symbol = reefLabel(world.symbol, fontSize: 34, heavy: true)
            symbol.zPosition = 1
            stop.addChild(symbol)

            let name = reefLabel(world.title, fontSize: 16, heavy: true)
            name.position = CGPoint(x: 0, y: -58)
            stop.addChild(name)

            if world.comingSoon {
                let soon = reefLabel("Coming soon", fontSize: 12, heavy: false)
                soon.position = CGPoint(x: 0, y: -78)
                stop.addChild(soon)
            } else {
                let star = starShape(radius: 7, filled: true)
                let tally = reefLabel("\(world.stars)/\(world.maxStars)", fontSize: 13, heavy: false)
                tally.horizontalAlignmentMode = .left
                let width = tally.frame.width + 18
                star.position = CGPoint(x: -width / 2 + 7, y: -79)
                tally.position = CGPoint(x: -width / 2 + 18, y: -79)
                stop.addChild(star)
                stop.addChild(tally)
            }

            if world.crown != .none {
                let crown = crownShape(width: 34, crown: world.crown)
                crown.position = CGPoint(x: 0, y: 54)
                crown.zPosition = 2
                stop.addChild(crown)
            }
            addChild(stop)
        }

        if centers.indices.contains(focus) {
            // To the right of the stop, swimming along the trail (the left edge can sit under the camera).
            fishHome = CGPoint(x: centers[focus].x + 66, y: centers[focus].y + 14)
            fish.zPosition = 3
            addChild(fish)
        } else {
            fish.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Where a world's stop sits on screen.
    func screenPoint(ofWorld index: Int) -> CGPoint { centers[index] }

    func handleTap(at point: CGPoint) {
        guard let index = centers.indices.first(where: { hypot(centers[$0].x - point.x, centers[$0].y - point.y) < 54 }),
              playable[index] else { return }
        onSelect?(index)
    }

    func update(time: CGFloat) {
        fish.position = CGPoint(x: fishHome.x, y: fishHome.y + sin(time * 2) * 4)
        fish.apply(radius: 18, facing: 1, tilt: cos(time * 2) * 0.08, stretchX: 1, stretchY: 1,
                   mouthOpen: 0, time: time, tailRate: 9)
    }
}

/// A world's levels as a winding path that scrolls sideways. Passed levels show stars; the next
/// level glows with the player fish beside it.
final class LevelMapNode: SKNode {
    var onSelect: ((Int) -> Void)?
    var onBack: (() -> Void)?

    private let content = SKNode()
    private let fish = FishNode(style: .player, isPlayer: true, tailPhase: 0)
    private var fishHome = CGPoint.zero
    private var centers: [CGPoint] = []
    private var radii: [CGFloat] = []
    private var playable: [Bool] = []
    private let backCenter: CGPoint
    private var minOffset: CGFloat = 0
    private var touchStart: CGPoint?
    private var lastX: CGFloat = 0
    private var dragging = false

    init(size: CGSize, title: String, color: SKColor, levels: [LevelStop], stars: (earned: Int, total: Int),
         crown: Crown, focus: Int) {
        backCenter = CGPoint(x: 46, y: size.height - 36)
        super.init()
        fish.setHeadwear(fishCrown(crown))

        let bed = seabed(size: size)
        bed.zPosition = -2
        addChild(bed)
        addChild(content)

        let spacing: CGFloat = 118, startX: CGFloat = 110
        centers = levels.indices.map { i in
            CGPoint(x: startX + spacing * CGFloat(i),
                    y: size.height * 0.44 + sin(CGFloat(i) * 1.1) * size.height * 0.16)
        }
        radii = levels.map { $0.isCheckpoint ? 34 : 28 }
        playable = levels.map { $0.state != .locked }

        let trail = dottedPath(through: centers)
        trail.zPosition = -1
        content.addChild(trail)

        for ((level, center), r) in zip(zip(levels, centers), radii) {
            content.addChild(stopNode(for: level, color: color, radius: r, at: center))
        }

        if centers.indices.contains(focus) {
            // Above the stop (the left edge can sit under the camera).
            fishHome = CGPoint(x: centers[focus].x, y: centers[focus].y + radii[focus] + 30)
            fish.zPosition = 3
            content.addChild(fish)
        }

        let contentWidth = startX * 2 + spacing * CGFloat(max(0, levels.count - 1))
        minOffset = min(0, size.width - contentWidth)
        if centers.indices.contains(focus) {
            content.position.x = (size.width / 2 - centers[focus].x).clamped(minOffset, 0)
        }

        addChild(header(size: size, title: title, stars: stars, crown: crown))
    }

    #if DEBUG
    /// Slides the path the least distance that leaves no stop within `clearance` of `x`. The
    /// simulator draws the Dynamic Island there, and a store capture fills it in from the water.
    func debugKeepClear(ofX x: CGFloat, clearance: CGFloat) {
        let start = content.position.x
        for step in 0...120 {
            for shift in [CGFloat(step), -CGFloat(step)] {
                let offset = start + shift
                guard offset <= 0, offset >= minOffset else { continue }
                if !centers.contains(where: { abs($0.x + offset - x) < clearance }) {
                    content.position.x = offset
                    return
                }
            }
        }
    }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Touches (scene coordinates; this node sits at the scene origin)

    /// Where a level's stop sits on screen at the current scroll.
    func screenPoint(ofLevel index: Int) -> CGPoint {
        CGPoint(x: centers[index].x + content.position.x, y: centers[index].y)
    }

    /// How far the path is scrolled: 0 at the start, negative as later levels come into view.
    var scrollOffset: CGFloat { content.position.x }

    func touchBegan(at point: CGPoint) {
        touchStart = point
        lastX = point.x
        dragging = false
    }

    func touchMoved(to point: CGPoint) {
        guard let start = touchStart else { return }
        if abs(point.x - start.x) > 10 { dragging = true }
        if dragging {
            content.position.x = (content.position.x + point.x - lastX).clamped(minOffset, 0)
        }
        lastX = point.x
    }

    func touchEnded(at point: CGPoint) {
        defer { touchStart = nil }
        guard touchStart != nil, !dragging else { return }
        if hypot(point.x - backCenter.x, point.y - backCenter.y) < 30 {
            onBack?()
            return
        }
        let local = CGPoint(x: point.x - content.position.x, y: point.y)
        if let index = centers.indices.first(where: { hypot(centers[$0].x - local.x, centers[$0].y - local.y) < radii[$0] + 14 }),
           playable[index] {
            onSelect?(index)
        }
    }

    func update(time: CGFloat) {
        fish.position = CGPoint(x: fishHome.x, y: fishHome.y + sin(time * 2) * 4)
        fish.apply(radius: 16, facing: 1, tilt: cos(time * 2) * 0.08, stretchX: 1, stretchY: 1,
                   mouthOpen: 0, time: time, tailRate: 9)
    }

    // MARK: Drawing

    private func stopNode(for level: LevelStop, color: SKColor, radius r: CGFloat, at center: CGPoint) -> SKNode {
        let stop = SKNode()
        stop.position = center

        let circle = SKShapeNode(circleOfRadius: r)
        let number: SKColor
        switch level.state {
        case .passed:
            circle.fillColor = color
            circle.strokeColor = level.isCheckpoint ? ReefStyle.gold : .white
            number = .white
        case .open:
            circle.fillColor = .white
            circle.strokeColor = level.isCheckpoint ? ReefStyle.gold : color
            number = color
            // Soft pulsing ring marks "play this next".
            let halo = SKShapeNode(circleOfRadius: r + 6)
            halo.strokeColor = SKColor(white: 1, alpha: 0.8)
            halo.lineWidth = 3
            halo.fillColor = .clear
            halo.zPosition = -0.5
            halo.run(.repeatForever(.sequence([
                .group([.scale(to: 1.25, duration: 0.9), .fadeOut(withDuration: 0.9)]),
                .scale(to: 1, duration: 0), .fadeAlpha(to: 1, duration: 0),
            ])))
            stop.addChild(halo)
        case .skipTest:
            circle.fillColor = SKColor(white: 1, alpha: 0.6)
            circle.strokeColor = ReefStyle.gold
            number = ReefStyle.ink
        case .locked:
            circle.fillColor = SKColor(white: 1, alpha: 0.15)
            circle.strokeColor = SKColor(white: 1, alpha: 0.3)
            number = SKColor(white: 1, alpha: 0.5)
        case .needsUnlock:
            circle.fillColor = SKColor(white: 1, alpha: 0.25)
            circle.strokeColor = level.isCheckpoint ? ReefStyle.gold : SKColor(white: 1, alpha: 0.6)
            number = SKColor(white: 1, alpha: 0.7)
            let lock = padlock(size: r * 0.8)
            lock.position = CGPoint(x: r * 0.72, y: r * 0.72)
            lock.zPosition = 2
            stop.addChild(lock)
        }
        circle.lineWidth = 4
        stop.addChild(circle)

        let label = reefLabel("\(level.number)", fontSize: level.isCheckpoint ? 24 : 21, heavy: true, color: number)
        label.zPosition = 1
        stop.addChild(label)

        let name = reefLabel(level.title, fontSize: 12, heavy: false,
                             color: SKColor(white: 1, alpha: level.state == .locked || level.state == .needsUnlock ? 0.55 : 0.95))
        name.position = CGPoint(x: 0, y: -r - 14)
        stop.addChild(name)
        if level.state == .skipTest {
            let skip = reefLabel("Skip test", fontSize: 11, heavy: true, color: ReefStyle.gold)
            skip.position = CGPoint(x: 0, y: -r - 29)
            stop.addChild(skip)
        }

        if level.state == .passed || level.stars > 0 {
            let stars = starRow(earned: level.stars, radius: 7, spacing: 17)
            stars.position = CGPoint(x: 0, y: r + 13)
            stars.zPosition = 2
            stop.addChild(stars)
        }
        return stop
    }

    private func header(size: CGSize, title: String, stars: (earned: Int, total: Int), crown: Crown) -> SKNode {
        let header = SKNode()
        header.zPosition = 5

        let back = SKShapeNode(circleOfRadius: 20)
        back.position = backCenter
        back.fillColor = SKColor(white: 0, alpha: 0.25)
        back.strokeColor = SKColor(white: 1, alpha: 0.5)
        back.lineWidth = 1.5
        let chevron = CGMutablePath()
        chevron.move(to: CGPoint(x: 4, y: 8))
        chevron.addLine(to: CGPoint(x: -4, y: 0))
        chevron.addLine(to: CGPoint(x: 4, y: -8))
        let arrow = SKShapeNode(path: chevron)
        arrow.strokeColor = .white
        arrow.lineWidth = 3
        arrow.lineCap = .round
        arrow.lineJoin = .round
        arrow.zPosition = 1
        back.addChild(arrow)
        header.addChild(back)

        let name = reefLabel(title, fontSize: 26, heavy: true)
        name.horizontalAlignmentMode = .left
        name.position = CGPoint(x: backCenter.x + 34, y: backCenter.y)
        header.addChild(name)

        var x = name.position.x + name.frame.width + 22
        let star = starShape(radius: 9, filled: true)
        star.position = CGPoint(x: x, y: backCenter.y)
        header.addChild(star)
        let tally = reefLabel("\(stars.earned)/\(stars.total)", fontSize: 16, heavy: true)
        tally.horizontalAlignmentMode = .left
        tally.position = CGPoint(x: x + 14, y: backCenter.y)
        header.addChild(tally)
        x += 14 + tally.frame.width + 24
        if crown != .none {
            let crownNode = crownShape(width: 28, crown: crown)
            crownNode.position = CGPoint(x: x, y: backCenter.y)
            header.addChild(crownNode)
        }
        return header
    }
}

/// A small padlock badge for levels that need the unlock.
private func padlock(size: CGFloat) -> SKNode {
    let node = SKNode()
    let backing = SKShapeNode(circleOfRadius: size * 0.62)
    backing.fillColor = ReefStyle.ink
    backing.strokeColor = .white
    backing.lineWidth = 2
    node.addChild(backing)
    let config = UIImage.SymbolConfiguration(pointSize: size * 0.62, weight: .bold)
    if let symbol = UIImage(systemName: "lock.fill", withConfiguration: config)?
        .withTintColor(.white, renderingMode: .alwaysOriginal) {
        let image = UIGraphicsImageRenderer(size: symbol.size).image { _ in symbol.draw(at: .zero) }
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.zPosition = 1
        node.addChild(sprite)
    }
    return node
}
