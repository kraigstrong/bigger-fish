import SpriteKit
import UIKit

/// Arcade-owned destinations; one prominent action keeps each result moving forward.
enum ArcadeResultAction: Equatable {
    case nextLevel, playAgain, tryAgain, levels, world, shop

    var title: String {
        switch self {
        case .nextLevel: "Next level"
        case .playAgain: "Play again"
        case .tryAgain: "Retry"
        case .levels: "Levels"
        case .world: "Back to world"
        case .shop: "Shop"
        }
    }

    /// `retryOnly`: the tutorial's, where being eaten just tries again. `shop`: an Open Water run's end, where the
    /// pearl shop sits between trying again and leaving.
    static func choices(passed: Bool, hasNext: Bool, retryOnly: Bool = false, shop: Bool = false) -> [Self] {
        if retryOnly && !passed { return [.tryAgain] }
        if shop && !passed { return [.tryAgain, .shop, .levels] }
        if passed && hasNext { return [.nextLevel, .playAgain, .levels] }
        return passed ? [.world, .playAgain] : [.tryAgain, .levels]
    }
}

/// Native accessibility actions for the SpriteKit result controls.
final class ArcadeResultAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}

final class ArcadeResultPanel: SKNode {
    var onSelect: ((ArcadeResultAction) -> Void)?
    private(set) var controls: [(action: ArcadeResultAction, frame: CGRect)] = []
    private(set) var primaryAction: ArcadeResultAction?

    /// `progress`, after a win: the world's pips and crown, in place of the detail line. `retryOnly`: one button, Retry,
    /// on a shorter card (the tutorial's). `shop`: the pearl shop's button too (an Open Water run's end).
    init(size: CGSize, passed: Bool, hasNext: Bool, detail: String, progress: WorldProgressStrip? = nil, retryOnly: Bool = false,
         shop: Bool = false) {
        super.init()
        let choices = ArcadeResultAction.choices(passed: passed, hasNext: hasNext, retryOnly: retryOnly, shop: shop)
        primaryAction = choices.first
        let maxWidth = size.width - 100
        let heading = text(passed ? "Level passed!" : "Try again!", size: 32, heavy: true)
        let line = text(detail, size: 20, heavy: false)
        if line.frame.width > maxWidth - 60 { line.fontSize *= (maxWidth - 60) / line.frame.width }
        let detailWidth = progress?.width ?? line.frame.width
        let width = min(maxWidth, max(430, heading.frame.width + 60, detailWidth + 60))
        // The pips and their caption take a little more room than the detail line; the buttons stay put. With no row of
        // smaller buttons, the card is shorter and everything moves down to fill it.
        let single = choices.count == 1
        let height: CGFloat = single ? 200 : progress == nil ? 256 : 284
        let lift: CGFloat = single ? -26 : 0
        let backing = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 24)
        backing.fillColor = passed ? SKColor(red: 0.10, green: 0.52, blue: 0.30, alpha: 0.92)
                                   : SKColor(white: 0, alpha: 0.65)
        backing.strokeColor = passed ? SKColor(white: 1, alpha: 0.6) : .clear
        backing.lineWidth = 2
        backing.zPosition = -1
        addChild(backing)
        addChild(heading)
        if let progress {
            heading.position = CGPoint(x: 0, y: 100)
            progress.position = CGPoint(x: 0, y: 60)
            addChild(progress)
        } else {
            heading.position = CGPoint(x: 0, y: 83 + lift)
            line.position = CGPoint(x: 0, y: 40 + lift)
            addChild(line)
        }
        for (i, action) in choices.enumerated() {
            let primary = i == 0
            let secondaryCount = choices.count - 1
            let buttonWidth = primary ? min(320, width - 48) : min(140, (width - 62) / CGFloat(secondaryCount))
            // 58 logical points remains a 44-point target on the smallest fitted phone playfield.
            let buttonHeight: CGFloat = 58
            let rowWidth = CGFloat(secondaryCount) * buttonWidth + CGFloat(secondaryCount - 1) * 14
            let center = primary ? CGPoint(x: 0, y: -17 + lift)
                : CGPoint(x: -rowWidth / 2 + buttonWidth / 2 + CGFloat(i - 1) * (buttonWidth + 14), y: -86)
            let frame = CGRect(x: center.x - buttonWidth / 2, y: center.y - buttonHeight / 2,
                               width: buttonWidth, height: buttonHeight)
            let button = SKShapeNode(rectOf: frame.size, cornerRadius: buttonHeight / 2)
            button.fillColor = primary ? .white : SKColor(white: 1, alpha: 0.06)
            button.strokeColor = primary ? .clear : SKColor(white: 1, alpha: 0.35)
            button.lineWidth = 1.5
            button.position = center
            let caption = text(action.title, size: primary ? 23 : 16, heavy: primary)
            caption.fontColor = primary ? SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1) : .white
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
