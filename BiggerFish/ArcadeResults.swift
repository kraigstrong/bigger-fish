import SpriteKit

/// Same result choices and button wording as Math Reef. Kept arcade-local during its review.
enum ArcadeResultAction: Equatable {
    case nextLevel, playAgain, tryAgain, levels

    var title: String {
        switch self {
        case .nextLevel: "Next level"
        case .playAgain: "Play again"
        case .tryAgain: "Try again"
        case .levels: "Levels"
        }
    }

    static func choices(passed: Bool, hasNext: Bool) -> [Self] {
        if passed && hasNext { return [.nextLevel, .playAgain, .levels] }
        return [passed ? .playAgain : .tryAgain, .levels]
    }
}

final class ArcadeResultPanel: SKNode {
    var onSelect: ((ArcadeResultAction) -> Void)?
    private(set) var controls: [(action: ArcadeResultAction, frame: CGRect)] = []

    init(size: CGSize, passed: Bool, hasNext: Bool, detail: String) {
        super.init()
        let choices = ArcadeResultAction.choices(passed: passed, hasNext: hasNext)
        let gap: CGFloat = 14, buttonWidth: CGFloat = 140
        let rowWidth = CGFloat(choices.count) * buttonWidth + CGFloat(choices.count - 1) * gap
        let maxWidth = size.width - 100
        let heading = text(passed ? "Level passed!" : "Try again!", size: 32, heavy: true)
        let line = text(detail, size: 20, heavy: false)
        if line.frame.width > maxWidth - 60 { line.fontSize *= (maxWidth - 60) / line.frame.width }
        let width = max(rowWidth, heading.frame.width, line.frame.width) + 60
        let height: CGFloat = 192
        let backing = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 24)
        backing.fillColor = passed ? SKColor(red: 0.10, green: 0.52, blue: 0.30, alpha: 0.92)
                                   : SKColor(white: 0, alpha: 0.65)
        backing.strokeColor = passed ? SKColor(white: 1, alpha: 0.6) : .clear
        backing.lineWidth = 2
        backing.zPosition = -1
        addChild(backing)
        heading.position = CGPoint(x: 0, y: 59)
        line.position = CGPoint(x: 0, y: 15)
        addChild(heading)
        addChild(line)
        for (i, action) in choices.enumerated() {
            let center = CGPoint(x: -rowWidth / 2 + buttonWidth / 2 + CGFloat(i) * (buttonWidth + gap), y: -54)
            let frame = CGRect(x: center.x - buttonWidth / 2, y: center.y - 24, width: buttonWidth, height: 48)
            let button = SKShapeNode(rectOf: frame.size, cornerRadius: 24)
            button.fillColor = SKColor(white: 1, alpha: 0.92)
            button.strokeColor = .clear
            button.position = center
            let caption = text(action.title, size: 19, heavy: true)
            caption.fontColor = SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1)
            button.addChild(caption)
            addChild(button)
            controls.append((action, frame))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func handleTap(at point: CGPoint) {
        guard let hit = controls.first(where: { $0.frame.contains(point) }) else { return }
        onSelect?(hit.action)
    }

    private func text(_ value: String, size: CGFloat, heavy: Bool) -> SKLabelNode {
        let node = SKLabelNode(fontNamed: heavy ? "AvenirNext-Heavy" : "AvenirNext-DemiBold")
        node.text = value
        node.fontSize = size
        node.fontColor = .white
        node.verticalAlignmentMode = .center
        return node
    }
}
