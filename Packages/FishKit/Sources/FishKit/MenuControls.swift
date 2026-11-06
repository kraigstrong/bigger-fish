import SpriteKit
import UIKit

// Menu controls in Bigger Fish's Settings language (its `SettingsView`): uppercase headings, plain rows, an accent color,
// on a deep-water backdrop. Bigger Fish's pause menu is drawn with them, and so are Math Reef's Settings and the
// grown-ups' screens behind it, each in its app's colors (`MenuTheme`).
//
// The scenes draw with `ignoresSiblingOrder`, so siblings at the same zPosition come out in any order: on a phone, a
// backdrop or a tile added first can be drawn over the text added after it. Everything that sits on something else
// gets its own depth.

/// An app's colors for its menus.
public struct MenuTheme {
    /// Switches when on, and the primary button.
    public let accent: UIColor
    /// Text and icons on the accent.
    public let onAccent: UIColor
    /// The backdrop's top and bottom.
    public let backdropTop: UIColor
    public let backdropBottom: UIColor

    public init(accent: UIColor, onAccent: UIColor, backdropTop: UIColor, backdropBottom: UIColor) {
        self.accent = accent
        self.onAccent = onAccent
        self.backdropTop = backdropTop
        self.backdropBottom = backdropBottom
    }
}

/// A menu's backdrop: the theme's deep water over the whole screen, what's behind it faintly showing.
public enum MenuBackdrop {
    /// How much of what's behind shows through: a little.
    public static let opacity: CGFloat = 0.93

    public static func node(size: CGSize, theme: MenuTheme) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture(theme), size: size)
        node.anchorPoint = .zero
        node.alpha = opacity
        // Under everything on it, the controls' own backgrounds included.
        node.zPosition = -10
        return node
    }

    private static func texture(_ theme: MenuTheme) -> SKTexture {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 256)).image { context in
            let colors = [theme.backdropTop.cgColor, theme.backdropBottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
        return SKTexture(image: image)
    }
}

/// A button row. `primary` is the accent's button (Bigger Fish's Resume); `secondary` is a Settings row: an icon and
/// its name on a faint rounded tile, and an optional symbol at its end (a link's arrow); `key` is the same tile with its
/// title in the middle (a keypad's digit).
public final class MenuButtonRow: SKNode {
    public enum Style { case primary, secondary, key }
    public static let size = CGSize(width: MenuSwitchRow.size.width, height: 46)
    public let size: CGSize

    /// `fontSize` overrides the style's.
    public init(title: String, symbol: String?, style: Style, theme: MenuTheme, size: CGSize = MenuButtonRow.size,
                trailing: String? = nil, fontSize: CGFloat? = nil) {
        self.size = size
        super.init()
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let label = SKLabelNode(fontNamed: style == .secondary ? "AvenirNext-DemiBold" : "AvenirNext-Heavy")
        label.text = title
        label.fontSize = fontSize ?? (style == .primary ? 19 : 17)
        label.verticalAlignmentMode = .center
        switch style {
        case .primary, .key:
            let primary = style == .primary
            let backing = SKShapeNode(rect: rect, cornerRadius: primary ? size.height / 2 : 12)
            backing.fillColor = primary ? theme.accent : UIColor(white: 1, alpha: 0.08)
            backing.strokeColor = .clear
            backing.zPosition = -1
            addChild(backing)
            let ink = primary ? theme.onAccent : .white
            label.fontColor = ink
            label.horizontalAlignmentMode = .center
            // The icon and title centered together.
            let icon = symbol.flatMap { SKSpriteNode.symbol($0, pointSize: 15, weight: .heavy, color: ink) }
            let gap: CGFloat = title.isEmpty ? 0 : 8, iconWidth = icon?.size.width ?? 0
            fit(label, width: size.width - 24 - iconWidth - gap)
            let total = iconWidth + (icon == nil ? 0 : gap) + label.frame.width
            icon?.position.x = -total / 2 + iconWidth / 2
            label.position.x = total / 2 - label.frame.width / 2
            if let icon { addChild(icon) }
        case .secondary:
            let tile = SKShapeNode(rect: rect, cornerRadius: 12)
            tile.fillColor = UIColor(white: 1, alpha: 0.08)
            tile.strokeColor = .clear
            tile.zPosition = -1
            addChild(tile)
            label.fontColor = .white
            label.horizontalAlignmentMode = .left
            label.position.x = -size.width / 2 + 46
            if let icon = symbol.flatMap({ SKSpriteNode.symbol($0, pointSize: 16, weight: .semibold) }) {
                icon.position.x = -size.width / 2 + 25
                addChild(icon)
            }
            var end = size.width / 2 - 14
            if let trailing, let mark = SKSpriteNode.symbol(trailing, pointSize: 13, weight: .bold) {
                mark.alpha = 0.6
                mark.position.x = end - mark.size.width / 2
                addChild(mark)
                end -= mark.size.width + 8
            }
            fit(label, width: end - label.position.x)
        }
        addChild(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The area a tap presses it in, in its parent's coordinates.
    public var hitFrame: CGRect {
        CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Shrinks a title too long for the row to fit it.
    private func fit(_ label: SKLabelNode, width: CGFloat) {
        if label.frame.width > width, width > 0 { label.setScale(width / label.frame.width) }
    }
}

/// A switch row, drawn like the toggles in Bigger Fish's Settings (`SettingsView`): an icon, its name, and an iOS-style
/// switch in the accent color when on. Its knob slides when it changes.
public final class MenuSwitchRow: SKNode {
    public static let size = CGSize(width: 236, height: 44)
    /// The switch's track and knob, at iOS's sizes.
    private static let track = CGSize(width: 51, height: 31)
    private static let knobInset: CGFloat = 2

    private let onTrack: SKShapeNode
    private let knob: SKShapeNode
    public private(set) var isOn: Bool

    public init(title: String, symbol: String, isOn: Bool, theme: MenuTheme) {
        self.isOn = isOn
        let track = Self.track
        let trackRect = CGRect(x: -track.width / 2, y: -track.height / 2, width: track.width, height: track.height)
        let offTrack = SKShapeNode(rect: trackRect, cornerRadius: track.height / 2)
        offTrack.fillColor = UIColor(white: 1, alpha: 0.18)
        offTrack.strokeColor = .clear
        onTrack = SKShapeNode(rect: trackRect, cornerRadius: track.height / 2)
        onTrack.fillColor = theme.accent
        onTrack.strokeColor = .clear
        let knobRadius = track.height / 2 - Self.knobInset
        knob = SKShapeNode(circleOfRadius: knobRadius)
        knob.fillColor = .white
        knob.strokeColor = UIColor(white: 0, alpha: 0.12)
        knob.lineWidth = 0.5
        knob.name = "knob"
        super.init()

        let switchX = Self.size.width / 2 - track.width / 2
        // The knob over the accent track, over the grey one.
        for (node, depth) in [(offTrack, CGFloat(-2)), (onTrack, -1), (knob, 0)] {
            node.position.x = switchX
            node.zPosition = depth
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
    public var hitFrame: CGRect {
        CGRect(x: position.x - Self.size.width / 2, y: position.y - Self.size.height / 2,
               width: Self.size.width, height: Self.size.height)
    }

    public func setOn(_ on: Bool, animated: Bool) {
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

/// The close button in a menu's top corner, as Bigger Fish's Settings draws it: an X in a faint ring.
public final class MenuCloseButton: SKNode {
    public static let radius: CGFloat = 22

    public override init() {
        super.init()
        let ring = SKShapeNode(circleOfRadius: Self.radius)
        ring.fillColor = UIColor(white: 1, alpha: 0.12)
        ring.strokeColor = UIColor(white: 1, alpha: 0.5)
        ring.lineWidth = 1.5
        ring.zPosition = -1
        addChild(ring)
        if let mark = SKSpriteNode.symbol("xmark", pointSize: 17, weight: .bold) { addChild(mark) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The area a tap presses it in, in its parent's coordinates.
    public var hitFrame: CGRect {
        CGRect(x: position.x - Self.radius, y: position.y - Self.radius, width: Self.radius * 2, height: Self.radius * 2)
    }
}

/// The small uppercase heading above a group of settings, as Settings draws it.
public func menuHeading(_ title: String) -> SKLabelNode {
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

extension SKSpriteNode {
    /// An SF Symbol as a sprite, drawn in `color`.
    public static func symbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .regular,
                              color: UIColor = .white) -> SKSpriteNode? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let drawn = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
        return SKSpriteNode(texture: SKTexture(image: drawn))
    }
}
