import SpriteKit
import UIKit

// The pause menu's controls, drawn in Settings' language (`SettingsView`): uppercase headings, plain rows, a gold
// accent, on the same deep-blue backdrop.

/// The pause menu's backdrop: Settings' deep-blue gradient over the whole screen, the paused game faintly showing.
enum MenuBackdrop {
    static func node(size: CGSize) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture, size: size)
        node.anchorPoint = .zero
        node.alpha = 0.93
        return node
    }

    private static let texture: SKTexture = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 256)).image { context in
            let colors = [UIColor(DeepEndColors.night).cgColor, UIColor(DeepEndColors.abyss).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
        return SKTexture(image: image)
    }()
}

/// A button row for the pause menu. `primary` is the game's gold button (Resume); `secondary` is a Settings row: an
/// icon and its name on a faint rounded tile.
final class MenuButtonRow: SKNode {
    enum Style { case primary, secondary }
    static let size = CGSize(width: MenuSwitchRow.size.width, height: 46)
    private static let navy = UIColor(red: 0.04, green: 0.12, blue: 0.24, alpha: 1)

    init(title: String, symbol: String, style: Style) {
        super.init()
        let size = Self.size
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let label = SKLabelNode(fontNamed: style == .primary ? "AvenirNext-Heavy" : "AvenirNext-DemiBold")
        label.text = title
        label.fontSize = style == .primary ? 19 : 17
        label.verticalAlignmentMode = .center
        switch style {
        case .primary:
            let pill = SKShapeNode(rect: rect, cornerRadius: size.height / 2)
            pill.fillColor = MenuSwitchRow.gold
            pill.strokeColor = .clear
            addChild(pill)
            label.fontColor = Self.navy
            label.horizontalAlignmentMode = .center
            // The icon and title centered together.
            let icon = SKSpriteNode.symbol(symbol, pointSize: 15, weight: .heavy, color: Self.navy)
            let gap: CGFloat = 8, iconWidth = icon?.size.width ?? 0
            let total = iconWidth + gap + label.frame.width
            icon?.position.x = -total / 2 + iconWidth / 2
            label.position.x = -total / 2 + iconWidth + gap + label.frame.width / 2
            if let icon { addChild(icon) }
        case .secondary:
            let tile = SKShapeNode(rect: rect, cornerRadius: 12)
            tile.fillColor = UIColor(white: 1, alpha: 0.08)
            tile.strokeColor = .clear
            addChild(tile)
            label.fontColor = .white
            label.horizontalAlignmentMode = .left
            label.position.x = -size.width / 2 + 46
            if let icon = SKSpriteNode.symbol(symbol, pointSize: 16, weight: .semibold) {
                icon.position.x = -size.width / 2 + 25
                addChild(icon)
            }
        }
        addChild(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The area a tap presses it in, in its parent's coordinates.
    var hitFrame: CGRect {
        CGRect(x: position.x - Self.size.width / 2, y: position.y - Self.size.height / 2,
               width: Self.size.width, height: Self.size.height)
    }
}

/// A switch row for the pause menu, drawn like the toggles in Settings (`SettingsView`): an icon, its name, and an
/// iOS-style switch, gold when on. Its knob slides when it changes.
final class MenuSwitchRow: SKNode {
    static let size = CGSize(width: 236, height: 44)
    /// The switch's track and knob, at iOS's sizes.
    private static let track = CGSize(width: 51, height: 31)
    private static let knobInset: CGFloat = 2
    static let gold = UIColor(DeepEndColors.gold)

    private let onTrack: SKShapeNode
    private let knob: SKShapeNode
    private(set) var isOn: Bool

    init(title: String, symbol: String, isOn: Bool) {
        self.isOn = isOn
        let track = Self.track
        let trackRect = CGRect(x: -track.width / 2, y: -track.height / 2, width: track.width, height: track.height)
        let offTrack = SKShapeNode(rect: trackRect, cornerRadius: track.height / 2)
        offTrack.fillColor = UIColor(white: 1, alpha: 0.18)
        offTrack.strokeColor = .clear
        onTrack = SKShapeNode(rect: trackRect, cornerRadius: track.height / 2)
        onTrack.fillColor = Self.gold
        onTrack.strokeColor = .clear
        let knobRadius = track.height / 2 - Self.knobInset
        knob = SKShapeNode(circleOfRadius: knobRadius)
        knob.fillColor = .white
        knob.strokeColor = UIColor(white: 0, alpha: 0.12)
        knob.lineWidth = 0.5
        super.init()

        let switchX = Self.size.width / 2 - track.width / 2
        for node in [offTrack, onTrack, knob] {
            node.position.x = switchX
            addChild(node)
        }
        if let icon = SKSpriteNode.symbol(symbol, pointSize: 16, weight: .semibold) {
            icon.position.x = -Self.size.width / 2 + 11
            addChild(icon)
        }
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = title
        label.fontSize = 17
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position.x = -Self.size.width / 2 + 32
        addChild(label)
        setOn(isOn, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The area a tap toggles it in, in its parent's coordinates: the whole row, not just the switch.
    var hitFrame: CGRect {
        CGRect(x: position.x - Self.size.width / 2, y: position.y - Self.size.height / 2,
               width: Self.size.width, height: Self.size.height)
    }

    func setOn(_ on: Bool, animated: Bool) {
        isOn = on
        let travel = Self.track.width / 2 - Self.track.height / 2
        let x = Self.size.width / 2 - Self.track.width / 2 + (on ? travel : -travel)
        knob.removeAllActions()
        onTrack.removeAllActions()
        if animated {
            let slide = SKAction.moveTo(x: x, duration: 0.18)
            slide.timingMode = .easeOut
            knob.run(slide)
            onTrack.run(.fadeAlpha(to: on ? 1 : 0, duration: 0.18))
        } else {
            knob.position.x = x
            onTrack.alpha = on ? 1 : 0
        }
    }
}

/// The small uppercase heading above a group of settings, as Settings draws it.
func menuHeading(_ title: String) -> SKLabelNode {
    let heading = SKLabelNode()
    heading.attributedText = NSAttributedString(string: title.uppercased(), attributes: [
        .font: UIFont(name: "AvenirNext-Heavy", size: 12) ?? .boldSystemFont(ofSize: 12),
        .foregroundColor: UIColor(white: 1, alpha: 0.6),
        .kern: 1.2,
    ])
    heading.horizontalAlignmentMode = .left
    heading.verticalAlignmentMode = .center
    return heading
}
