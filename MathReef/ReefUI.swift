import SpriteKit
import UIKit

// Shared drawing helpers for Math Reef: labels, stars, crowns, and each world's look.
// Stars and crowns are drawn as shapes: symbol characters fall back to an odd-looking font.

enum ReefStyle {
    static let ink = SKColor(red: 0.05, green: 0.18, blue: 0.35, alpha: 1)
    static let gold = SKColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1)
    static let silver = SKColor(red: 0.85, green: 0.88, blue: 0.93, alpha: 1)
    static let sand = SKColor(red: 0.93, green: 0.82, blue: 0.58, alpha: 1)

    static func color(for worldID: String) -> SKColor {
        switch worldID {
        case "addition": SKColor(red: 0.98, green: 0.45, blue: 0.42, alpha: 1)
        case "subtraction": SKColor(red: 0.30, green: 0.58, blue: 0.98, alpha: 1)
        case "multiplication": SKColor(red: 0.62, green: 0.45, blue: 0.95, alpha: 1)
        case "division": SKColor(red: 0.16, green: 0.72, blue: 0.58, alpha: 1)
        default: SKColor(red: 0.95, green: 0.40, blue: 0.70, alpha: 1)
        }
    }

    static func symbol(for worldID: String) -> String {
        switch worldID {
        case "addition": "+"
        case "subtraction": "−"
        case "multiplication": "×"
        case "division": "÷"
        default: "x²"
        }
    }
}

enum Crown: Equatable {
    case none
    /// Every level in the world passed.
    case silver
    /// Three stars on every level in the world.
    case gold
}

/// Superscript digits (², ³) are drawn as small raised digits: in the heavy display font the Unicode
/// superscript glyphs are large enough that "3²" can read as "32".
func reefLabel(_ text: String, fontSize: CGFloat, heavy: Bool, color: SKColor = .white) -> SKLabelNode {
    let name = heavy ? "AvenirNext-Heavy" : "AvenirNext-DemiBold"
    let font = UIFont(name: name, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: heavy ? .heavy : .semibold)
    let small = font.withSize(fontSize * 0.58)
    let superscripts: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]

    let styled = NSMutableAttributedString()
    for character in text {
        if let digit = superscripts.firstIndex(of: character) {
            styled.append(NSAttributedString(string: "\(digit)", attributes: [
                .font: small, .foregroundColor: color, .baselineOffset: fontSize * 0.38,
            ]))
        } else {
            styled.append(NSAttributedString(string: String(character), attributes: [
                .font: font, .foregroundColor: color,
            ]))
        }
    }

    let label = SKLabelNode()
    label.attributedText = styled
    label.verticalAlignmentMode = .center
    label.horizontalAlignmentMode = .center
    return label
}

/// An SF Symbol as a sprite, drawn in `color` (the settings gear, the tutorial's finger).
func reefSymbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .semibold, color: UIColor = .white) -> SKSpriteNode? {
    let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let symbol = UIImage(systemName: name, withConfiguration: config)?
        .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
    let image = UIGraphicsImageRenderer(size: symbol.size).image { _ in symbol.draw(at: .zero) }
    return SKSpriteNode(texture: SKTexture(image: image))
}

/// A five-point star; filled gold when earned, a faint outline when not.
func starShape(radius r: CGFloat, filled: Bool) -> SKShapeNode {
    let path = CGMutablePath()
    for i in 0..<10 {
        let angle = CGFloat(i) * .pi / 5 + .pi / 2
        let radius = i.isMultiple(of: 2) ? r : r * 0.45
        let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    let star = SKShapeNode(path: path)
    star.fillColor = filled ? ReefStyle.gold : SKColor(white: 1, alpha: 0.12)
    star.strokeColor = filled ? SKColor(red: 0.85, green: 0.55, blue: 0.05, alpha: 1) : SKColor(white: 1, alpha: 0.5)
    star.lineWidth = max(1, r * 0.14)
    star.lineJoin = .round
    return star
}

/// A three-point crown with little jewels.
func crownShape(width w: CGFloat, crown: Crown) -> SKShapeNode {
    let h = w * 0.7
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -w / 2, y: -h / 2))
    path.addLine(to: CGPoint(x: -w / 2, y: h / 2))
    path.addLine(to: CGPoint(x: -w / 4, y: 0))
    path.addLine(to: CGPoint(x: 0, y: h / 2))
    path.addLine(to: CGPoint(x: w / 4, y: 0))
    path.addLine(to: CGPoint(x: w / 2, y: h / 2))
    path.addLine(to: CGPoint(x: w / 2, y: -h / 2))
    path.closeSubpath()
    let shape = SKShapeNode(path: path)
    shape.fillColor = crown == .gold ? ReefStyle.gold : ReefStyle.silver
    shape.strokeColor = crown == .gold ? SKColor(red: 0.85, green: 0.55, blue: 0.05, alpha: 1) : SKColor(white: 0.55, alpha: 1)
    shape.lineWidth = max(1.5, w * 0.06)
    shape.lineJoin = .round
    for x in [-w / 2, 0, w / 2] {
        let jewel = SKShapeNode(circleOfRadius: w * 0.08)
        jewel.position = CGPoint(x: x, y: h / 2)
        jewel.fillColor = SKColor(red: 0.95, green: 0.30, blue: 0.40, alpha: 1)
        jewel.strokeColor = .clear
        jewel.zPosition = 1
        shape.addChild(jewel)
    }
    return shape
}

/// The crown the player fish wears, sized for `FishNode.setHeadwear`; nil for no crown.
func fishCrown(_ crown: Crown) -> SKNode? {
    crown == .none ? nil : crownShape(width: 24, crown: crown)
}

/// A row of three stars, `earned` of them filled.
func starRow(earned: Int, radius: CGFloat, spacing: CGFloat) -> SKNode {
    let row = SKNode()
    for i in 0..<3 {
        let star = starShape(radius: radius, filled: i < earned)
        star.position = CGPoint(x: CGFloat(i - 1) * spacing, y: i == 1 ? radius * 0.35 : 0)
        row.addChild(star)
    }
    return row
}

/// Sandy seabed with a few coral bumps along the bottom of the screen.
func seabed(size: CGSize) -> SKNode {
    let node = SKNode()
    let path = CGMutablePath()
    path.move(to: .zero)
    path.addLine(to: CGPoint(x: 0, y: size.height * 0.14))
    let waves = 5
    for i in 0..<waves {
        let x0 = size.width * CGFloat(i) / CGFloat(waves), x1 = size.width * CGFloat(i + 1) / CGFloat(waves)
        path.addQuadCurve(to: CGPoint(x: x1, y: size.height * (i.isMultiple(of: 2) ? 0.12 : 0.15)),
                          control: CGPoint(x: (x0 + x1) / 2, y: size.height * (i.isMultiple(of: 2) ? 0.19 : 0.09)))
    }
    path.addLine(to: CGPoint(x: size.width, y: 0))
    path.closeSubpath()
    let sand = SKShapeNode(path: path)
    sand.fillColor = ReefStyle.sand.withAlphaComponent(0.85)
    sand.strokeColor = .clear
    node.addChild(sand)

    let corals: [(x: CGFloat, r: CGFloat, color: SKColor)] = [
        (0.06, 16, SKColor(red: 0.98, green: 0.45, blue: 0.55, alpha: 0.9)),
        (0.09, 10, SKColor(red: 0.98, green: 0.65, blue: 0.35, alpha: 0.9)),
        (0.47, 12, SKColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 0.9)),
        (0.51, 18, SKColor(red: 0.62, green: 0.45, blue: 0.95, alpha: 0.9)),
        (0.93, 14, SKColor(red: 0.98, green: 0.45, blue: 0.55, alpha: 0.9)),
    ]
    for coral in corals {
        let blob = SKShapeNode(ellipseOf: CGSize(width: coral.r * 2, height: coral.r * 2.4))
        blob.position = CGPoint(x: size.width * coral.x, y: size.height * 0.12 + coral.r * 0.6)
        blob.fillColor = coral.color
        blob.strokeColor = .clear
        blob.zPosition = 1
        node.addChild(blob)
    }
    return node
}

/// Dotted trail through `points`, gently curved between each pair.
func dottedPath(through points: [CGPoint], spacing: CGFloat = 16) -> SKNode {
    let node = SKNode()
    for (from, to) in zip(points, points.dropFirst()) {
        let control = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + (to.y > from.y ? -24 : 24))
        let steps = max(2, Int(hypot(to.x - from.x, to.y - from.y) / spacing))
        for step in 1..<steps {
            let t = CGFloat(step) / CGFloat(steps)
            let u = 1 - t
            let point = CGPoint(
                x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                y: u * u * from.y + 2 * u * t * control.y + t * t * to.y
            )
            let dot = SKShapeNode(circleOfRadius: 3)
            dot.position = point
            dot.fillColor = SKColor(white: 1, alpha: 0.45)
            dot.strokeColor = .clear
            node.addChild(dot)
        }
    }
    return node
}
