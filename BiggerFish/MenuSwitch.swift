import SpriteKit
import UIKit

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
