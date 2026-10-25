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
    private(set) var headingText: String
    private(set) var noteText: String?
    /// The pearls on the Shop button: yours to spend, and the count it shows while it counts up to them.
    private(set) var shopPearls: Int?
    private(set) var shownShopPearls: Int?
    private var shopButton: SKNode?

    /// `progress`, after a win: the world's pips and crown, in place of the detail line. `retryOnly`: one button, Retry,
    /// on a shorter card (the tutorial's). `heading`: in place of "Level passed!" or "Try again!". `note`: a second,
    /// smaller line under the detail (an Open Water run's best). `shopPearls`: the pearl shop's button too, showing the
    /// pearls you have to spend (an Open Water run's end).
    init(size: CGSize, passed: Bool, hasNext: Bool, detail: String, progress: WorldProgressStrip? = nil, retryOnly: Bool = false,
         heading headingOverride: String? = nil, note: String? = nil, shopPearls: Int? = nil) {
        headingText = headingOverride ?? (passed ? "Level passed!" : "Try again!")
        noteText = progress == nil ? note : nil
        self.shopPearls = shopPearls
        shownShopPearls = shopPearls
        super.init()
        let choices = ArcadeResultAction.choices(passed: passed, hasNext: hasNext, retryOnly: retryOnly, shop: shopPearls != nil)
        primaryAction = choices.first
        let maxWidth = size.width - 100
        let heading = text(headingText, size: 32, heavy: true)
        let line = text(detail, size: 20, heavy: false)
        if line.frame.width > maxWidth - 60 { line.fontSize *= (maxWidth - 60) / line.frame.width }
        let detailWidth = progress?.width ?? line.frame.width
        let width = min(maxWidth, max(430, heading.frame.width + 60, detailWidth + 60))
        // The pips and their caption take a little more room than the detail line; the buttons stay put. With no row of
        // smaller buttons, the card is shorter and everything moves down to fill it.
        // A note under the detail takes the same room.
        let single = choices.count == 1
        let height: CGFloat = single ? 200 : progress == nil && noteText == nil ? 256 : 284
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
        } else if let noteText {
            heading.position = CGPoint(x: 0, y: 100 + lift)
            line.position = CGPoint(x: 0, y: 62 + lift)
            addChild(line)
            let note = text(noteText, size: 17, heavy: false)
            note.fontColor = SKColor(white: 1, alpha: 0.8)
            note.position = CGPoint(x: 0, y: 32 + lift)
            addChild(note)
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
            if action == .shop, let shopPearls {
                button.addChild(shopCaption(shopPearls))
                shopButton = button
            } else {
                let caption = text(action.title, size: primary ? 23 : 16, heavy: primary)
                caption.fontColor = primary ? SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1) : .white
                button.addChild(caption)
            }
            addChild(button)
            controls.append((action, frame))
        }
    }

    /// The pearls you have to spend changed (bought something in the shop, over this card): the Shop button shows them,
    /// at once.
    func showShopPearls(_ pearls: Int) {
        guard shopPearls != nil else { return }
        removeAction(forKey: Self.countKey)
        shopPearls = pearls
        showCaption(pearls)
    }

    /// The run's pearls joining the rest: the Shop button counts up to what you have from `start`, a pearl at a time,
    /// after `delay` seconds.
    func countShopPearls(from start: Int, after delay: TimeInterval) {
        guard let end = shopPearls, start < end else { return }
        showCaption(start)
        let step = min(0.08, 0.8 / Double(end - start))
        let tick = SKAction.run { [weak self] in
            guard let self, let shown = self.shownShopPearls, let end = self.shopPearls else { return }
            self.showCaption(min(shown + 1, end))
        }
        run(.sequence([.wait(forDuration: delay), .repeat(.sequence([tick, .wait(forDuration: step)]), count: end - start)]),
            withKey: Self.countKey)
    }

    private static let countKey = "countShopPearls"

    private func showCaption(_ pearls: Int) {
        guard let shopButton else { return }
        shownShopPearls = pearls
        shopButton.childNode(withName: Self.shopCaptionName)?.removeFromParent()
        shopButton.addChild(shopCaption(pearls))
    }

    /// What VoiceOver says for a button: its title, and on the Shop button, your pearls.
    func spokenTitle(_ action: ArcadeResultAction) -> String {
        guard action == .shop, let shopPearls else { return action.title }
        return "\(action.title), \(shopPearls == 1 ? "1 pearl" : "\(shopPearls) pearls")"
    }

    private static let shopCaptionName = "shopCaption"

    /// The Shop button's caption: "Shop", then a pearl and how many you have.
    private func shopCaption(_ pearls: Int) -> SKNode {
        let caption = SKNode()
        caption.name = Self.shopCaptionName
        // Over the button, its pearl's glint over the pearl.
        caption.zPosition = 1
        let word = text(ArcadeResultAction.shop.title, size: 16, heavy: false)
        let count = text("\(pearls)", size: 16, heavy: true)
        let pearl = PearlShopArt.pearlIcon(radius: 6)
        let gap: CGFloat = 8, icon: CGFloat = 12, iconGap: CGFloat = 4
        let left = -(word.frame.width + gap + icon + iconGap + count.frame.width) / 2
        word.horizontalAlignmentMode = .left
        word.position = CGPoint(x: left, y: 0)
        pearl.position = CGPoint(x: left + word.frame.width + gap + icon / 2, y: 0)
        count.horizontalAlignmentMode = .left
        count.position = CGPoint(x: left + word.frame.width + gap + icon + iconGap, y: 0)
        for part in [word, pearl, count] { caption.addChild(part) }
        return caption
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
