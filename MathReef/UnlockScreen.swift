import FishKit
import SpriteKit
import UIKit

// The grown-ups' unlock screen, behind the parental gate: the moment a parent decides. Bigger Fish's `UnlockView` sells
// what's inside with a clip of each world; Math Reef has no clips, so each world shows as the reef draws it, in its color
// and symbol, with its grades, the first and the hardest question it asks, and a pip for each of its levels, the free
// ones lit. Then what's free against everything, one purchase for the whole family, the App Store's price, and Restore
// and Not now. Math Reef is in the Kids category (App Store guidelines 1.3 and 3.1.1): the price is shown plainly, with
// no urgency, discounts, or pressure. The purchase itself is the scene's (`buyUnlock`, and ReefUnlock.swift).

/// What the unlock opens, world by world, from the curriculum and the free sample.
enum UnlockOffer {
    struct WorldSummary {
        let id: String
        let title: String
        let grades: String
        let topics: [String]
        let levels: Int
        let freeLevels: Int
        /// Its skip tests, drawn bigger, as on the level path.
        let checkpoints: Set<Int>
        /// Its first question, and the hardest in its last level that isn't a skip test.
        let firstQuestion: String
        let hardestQuestion: String
    }

    static let worlds: [WorldSummary] = Curriculum.worlds.filter { !$0.comingSoon }.map { world in
        let lessons = world.levels.filter { !$0.isCheckpoint }
        return WorldSummary(
            id: world.id, title: world.title, grades: grades(for: world.id), topics: topics(for: world.id),
            levels: world.levels.count, freeLevels: FreeSample.freeLevels(in: world),
            checkpoints: Set(world.levels.indices.filter { world.levels[$0].isCheckpoint }),
            firstQuestion: world.levels.first?.facts.min { $0.answer < $1.answer }?.prompt ?? "",
            hardestQuestion: lessons.last?.facts.max { $0.answer < $1.answer }?.prompt ?? ""
        )
    }

    static var totalLevels: Int { worlds.map(\.levels).reduce(0, +) }
    static var totalFree: Int { worlds.map(\.freeLevels).reduce(0, +) }

    /// The grades where a world's math is usually learned.
    static func grades(for worldID: String) -> String {
        switch worldID {
        case "addition", "subtraction": "Grades 1–2"
        case "multiplication", "division": "Grades 3–4"
        case "exponents": "Grade 5"
        default: ""
        }
    }

    /// A world's levels in a few words, shown where the screen has the height (an iPad).
    static func topics(for worldID: String) -> [String] {
        switch worldID {
        case "addition": ["Facts to 20", "Make 10, doubles", "2-digit, carrying"]
        case "subtraction": ["Facts to 20", "Back past 10", "2-digit, borrowing"]
        case "multiplication": ["Tables to × 12", "× tens", "2-digit × 1-digit"]
        case "division": ["÷ facts to 12", "÷ into tens", "2-digit ÷ 1-digit"]
        case "exponents": ["Squares", "Cubes", "Both, mixed"]
        default: []
        }
    }
}

/// The unlock screen, over the whole scene. It's laid out for the smallest phone (an iPhone SE) and drawn bigger on
/// bigger screens, as much bigger as fits both ways; where that leaves height to spare (an iPad), each world lists its
/// topics too. Every node has its own depth: the scene ignores sibling order.
final class UnlockScreen: SKNode {
    /// The smallest screen it's laid out for: an iPhone SE's, in landscape.
    static let designSize = CGSize(width: 667, height: 375)

    /// The screen's buttons, in the scene's coordinates (this node sits at the scene's origin), for the scene's touches.
    /// The last is the rest of the screen, which does nothing: a tap off the buttons doesn't close it, Not now does.
    private(set) var buttons: [(frame: CGRect, action: () -> Void)] = []
    /// Whether the worlds list their topics: on a screen with the height for them.
    let showsTopics: Bool

    private static let topicsHeight: CGFloat = 50

    /// How far the worlds keep from the screen's sides, in points: clear of the Dynamic Island or notch on the wide
    /// phones that have one (a landscape safe-area inset of up to 62), as the reef map's stops are.
    static func sideMargin(for size: CGSize) -> CGFloat {
        size.width / size.height > 2 ? 64 : 22
    }

    /// `featured` is the world the child was in, if any, ringed brighter.
    init(size: CGSize, price: String?, featured: String?,
         onBuy: @escaping () -> Void, onRestore: @escaping () -> Void, onClose: @escaping () -> Void) {
        let scale = max(1, min(size.width / Self.designSize.width, size.height / Self.designSize.height))
        let width = size.width / scale, height = size.height / scale
        let spare = height - Self.designSize.height
        showsTopics = spare >= Self.topicsHeight
        super.init()
        zPosition = 0

        // Deep water, darker toward the bottom, so nothing behind shows through.
        let backdrop = SKSpriteNode(texture: Self.backdropTexture(), size: size)
        backdrop.anchorPoint = .zero
        backdrop.zPosition = 0
        addChild(backdrop)

        let content = SKNode()
        content.setScale(scale)
        content.zPosition = 1
        addChild(content)

        // The height left over, shared between the gaps above, between, and below.
        let gap = max(0, spare - (showsTopics ? Self.topicsHeight : 0)) / 4

        let title = reefLabel("Unlock the whole reef", fontSize: 28, heavy: true)
        title.position = CGPoint(x: width / 2 + 20, y: height - 32 - gap)
        title.zPosition = 1
        content.addChild(title)
        content.addChild(swimmingFish(at: CGPoint(x: title.position.x - title.frame.width / 2 - 34, y: title.position.y)))

        let subtitle = reefLabel(
            "Try \(UnlockOffer.totalFree) levels free. The unlock opens all \(UnlockOffer.totalLevels), in all five worlds.",
            fontSize: 15, heavy: false, color: SKColor(white: 1, alpha: 0.9)
        )
        subtitle.position = CGPoint(x: width / 2, y: title.position.y - 30)
        subtitle.zPosition = 1
        content.addChild(subtitle)

        // The worlds, side by side.
        let worlds = UnlockOffer.worlds
        let margin = Self.sideMargin(for: size) / scale, between: CGFloat = 10
        let cardWidth = min(150, (width - margin * 2 - between * CGFloat(worlds.count - 1)) / CGFloat(worlds.count))
        let rowWidth = cardWidth * CGFloat(worlds.count) + between * CGFloat(worlds.count - 1)
        let cardTop = subtitle.position.y - 26 - gap
        for (index, world) in worlds.enumerated() {
            let card = worldCard(world, width: cardWidth, featured: world.id == featured)
            card.position = CGPoint(x: (width - rowWidth) / 2 + cardWidth / 2 + CGFloat(index) * (cardWidth + between),
                                    y: cardTop)
            card.zPosition = 1
            content.addChild(card)
        }

        // The buttons along the bottom, clear of the home indicator, with the purchase in the middle.
        let buttonsY = 40 + gap
        let note = reefLabel("A one-time purchase, shared with your family through Family Sharing.", fontSize: 14,
                             heavy: false, color: SKColor(white: 1, alpha: 0.85))
        note.position = CGPoint(x: width / 2, y: buttonsY + 46)
        note.zPosition = 1
        content.addChild(note)

        let row: [(title: String, primary: Bool, action: () -> Void)] = [
            ("Restore purchases", false, onRestore),
            (price.map { "Unlock for \($0)" } ?? "Unlock", true, onBuy),
            ("Not now", false, onClose),
        ]
        let pills = row.map { pill($0.title, primary: $0.primary) }
        let spacing: CGFloat = 14
        var x = (width - pills.map(\.width).reduce(0, +) - spacing * CGFloat(pills.count - 1)) / 2
        for (pill, item) in zip(pills, row) {
            pill.node.position = CGPoint(x: x + pill.width / 2, y: buttonsY)
            pill.node.zPosition = 1
            content.addChild(pill.node)
            let frame = CGRect(x: x, y: buttonsY - pill.height / 2, width: pill.width, height: pill.height)
            buttons.append((CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale,
                                   height: frame.height * scale), item.action))
            x += pill.width + spacing
        }
        buttons.append((CGRect(origin: .zero, size: size), {}))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Drawing

    /// A world as the reef draws it: its symbol on a coral stop in its color, its name and grades, its first and hardest
    /// questions, and a pip for each level, the free ones white. The card's top is at the node's origin.
    private func worldCard(_ world: UnlockOffer.WorldSummary, width: CGFloat, featured: Bool) -> SKNode {
        let color = ReefStyle.color(for: world.id)
        let card = SKNode()
        let height: CGFloat = 166 + (showsTopics ? Self.topicsHeight : 0)

        let backing = SKShapeNode(rect: CGRect(x: -width / 2, y: -height, width: width, height: height), cornerRadius: 16)
        backing.fillColor = color.withAlphaComponent(featured ? 0.3 : 0.18)
        backing.strokeColor = color.withAlphaComponent(featured ? 1 : 0.7)
        backing.lineWidth = featured ? 3 : 1.5
        backing.zPosition = 0
        card.addChild(backing)

        let stop = SKShapeNode(circleOfRadius: 22)
        stop.position = CGPoint(x: 0, y: -32)
        stop.fillColor = color
        stop.strokeColor = .white
        stop.lineWidth = 3
        stop.zPosition = 1
        card.addChild(stop)
        let symbol = reefLabel(ReefStyle.symbol(for: world.id), fontSize: 22, heavy: true)
        symbol.position = stop.position
        symbol.zPosition = 2
        card.addChild(symbol)

        var y: CGFloat = -70
        let name = fitted(reefLabel(world.title, fontSize: 15, heavy: true), width: width - 12)
        name.position = CGPoint(x: 0, y: y)
        name.zPosition = 1
        card.addChild(name)
        y -= 18
        let grades = reefLabel(world.grades, fontSize: 12, heavy: true, color: color.mixed(with: .white, by: 0.45))
        grades.position = CGPoint(x: 0, y: y)
        grades.zPosition = 1
        card.addChild(grades)

        if showsTopics {
            y -= 6
            for topic in world.topics {
                y -= 14
                let line = fitted(reefLabel(topic, fontSize: 11, heavy: false, color: SKColor(white: 1, alpha: 0.85)),
                                  width: width - 12)
                line.position = CGPoint(x: 0, y: y)
                line.zPosition = 1
                card.addChild(line)
            }
            y -= Self.topicsHeight - 6 - 14 * CGFloat(world.topics.count)
        }

        y -= 22
        let questions = questionRange(from: world.firstQuestion, to: world.hardestQuestion)
        fitted(questions, width: width - 14)
        questions.position = CGPoint(x: 0, y: y)
        questions.zPosition = 1
        card.addChild(questions)

        y -= 24
        let pips = levelPips(world, color: color, width: width - 18)
        pips.position = CGPoint(x: 0, y: y)
        pips.zPosition = 1
        card.addChild(pips)

        y -= 18
        let caption = reefLabel("\(world.levels) levels, \(world.freeLevels) free", fontSize: 11, heavy: false,
                                color: SKColor(white: 1, alpha: 0.85))
        caption.position = CGPoint(x: 0, y: y)
        caption.zPosition = 1
        card.addChild(caption)
        return card
    }

    /// "3 + 1 to 47 + 49": the first question, the word "to", and the hardest.
    private func questionRange(from first: String, to hardest: String) -> SKNode {
        let parts = [reefLabel(first, fontSize: 13, heavy: true),
                     reefLabel("to", fontSize: 11, heavy: false, color: SKColor(white: 1, alpha: 0.7)),
                     reefLabel(hardest, fontSize: 13, heavy: true)]
        let space: CGFloat = 5
        var x = -(parts.map(\.frame.width).reduce(0, +) + space * CGFloat(parts.count - 1)) / 2
        let node = SKNode()
        for part in parts {
            part.horizontalAlignmentMode = .left
            part.position = CGPoint(x: x, y: 0)
            part.zPosition = 0
            node.addChild(part)
            x += part.frame.width + space
        }
        return node
    }

    /// A pip for each level, in order along a line: the free ones white, the rest the world's color, skip tests bigger
    /// and ringed gold, as on the level path.
    private func levelPips(_ world: UnlockOffer.WorldSummary, color: SKColor, width: CGFloat) -> SKNode {
        let node = SKNode()
        let spacing = min(8, width / CGFloat(max(1, world.levels - 1)))
        let start = -spacing * CGFloat(world.levels - 1) / 2
        for index in 0..<world.levels {
            let checkpoint = world.checkpoints.contains(index)
            let pip = SKShapeNode(circleOfRadius: checkpoint ? 3.6 : 2.6)
            pip.position = CGPoint(x: start + CGFloat(index) * spacing, y: 0)
            pip.fillColor = index < world.freeLevels ? .white : color
            pip.strokeColor = checkpoint ? ReefStyle.gold : .clear
            pip.lineWidth = checkpoint ? 1.2 : 0
            // Each over the one before: a skip test's ring meets its neighbors, and the scene ignores sibling order.
            pip.zPosition = CGFloat(index) / 100
            node.addChild(pip)
        }
        return node
    }

    /// A button: the purchase gold, the others outlined.
    private func pill(_ title: String, primary: Bool) -> (node: SKNode, width: CGFloat, height: CGFloat) {
        let text = reefLabel(title, fontSize: primary ? 19 : 15, heavy: true, color: primary ? ReefStyle.ink : .white)
        let height: CGFloat = primary ? 46 : 40
        let width = max(primary ? 180 : 110, text.frame.width + (primary ? 48 : 32))
        let node = SKNode()
        let backing = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height / 2)
        backing.fillColor = primary ? ReefStyle.gold : SKColor(white: 1, alpha: 0.12)
        backing.strokeColor = primary ? .clear : SKColor(white: 1, alpha: 0.6)
        backing.lineWidth = primary ? 0 : 1.5
        backing.zPosition = 0
        node.addChild(backing)
        text.zPosition = 1
        node.addChild(text)
        return (node, width, height)
    }

    /// The player's fish, bobbing beside the title as it does on the maps.
    private func swimmingFish(at home: CGPoint) -> SKNode {
        let fish = FishNode(style: .player, isPlayer: true, tailPhase: 0)
        fish.position = home
        fish.zPosition = 5
        let animate: (SKNode, CGFloat) -> Void = { node, time in
            guard let fish = node as? FishNode else { return }
            fish.position = CGPoint(x: home.x, y: home.y + sin(time * 2) * 4)
            fish.apply(radius: 16, facing: 1, tilt: cos(time * 2) * 0.08, stretchX: 1, stretchY: 1, mouthOpen: 0,
                       time: time, tailRate: 9)
        }
        animate(fish, 0)
        // An action rather than the scene's frame loop, so the screen needs nothing from it: as long as it's open.
        fish.run(.customAction(withDuration: 24 * 60 * 60, actionBlock: animate))
        return fish
    }

    private static func backdropTexture() -> SKTexture {
        let size = CGSize(width: 4, height: 64)
        // Settings' deep water (SettingsMenu.swift), opaque.
        let colors = [MenuTheme.reef.backdropTop.cgColor, MenuTheme.reef.backdropBottom.cgColor] as CFArray
        let image = UIGraphicsImageRenderer(size: size).image { context in
            // The image's top is the screen's top.
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }

    /// Scales `node` down to fit `width`, if it's wider.
    @discardableResult
    private func fitted<Node: SKNode>(_ node: Node, width: CGFloat) -> Node {
        let natural = node.calculateAccumulatedFrame().width
        if natural > width { node.setScale(width / natural) }
        return node
    }
}

private extension SKColor {
    /// This color moved `amount` of the way to `other`.
    func mixed(with other: SKColor, by amount: CGFloat) -> SKColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return SKColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount,
                       alpha: a1 + (a2 - a1) * amount)
    }
}
