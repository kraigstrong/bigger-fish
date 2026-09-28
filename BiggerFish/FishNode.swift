import SpriteKit

/// Purely cosmetic variation. Nothing here correlates with size or affects gameplay.
struct FishStyle {
    enum Pattern: CaseIterable { case plain, spots, stripes }
    enum Tail: CaseIterable { case fork, fan, point }

    var body: SKColor
    var accent: SKColor
    var pattern: Pattern
    var tail: Tail
    var eyeScale: CGFloat
    var hasDorsalFin: Bool

    /// The player's warm orange is deliberately absent from the AI palette so it's easy to track.
    static let player = FishStyle(
        body: SKColor(red: 1.00, green: 0.62, blue: 0.16, alpha: 1),
        accent: SKColor(red: 1.00, green: 0.84, blue: 0.40, alpha: 1),
        pattern: .plain,
        tail: .fork,
        eyeScale: 1.1,
        hasDorsalFin: true
    )

    private static let palette: [(body: SKColor, accent: SKColor)] = [
        (SKColor(red: 0.18, green: 0.77, blue: 0.71, alpha: 1), SKColor(red: 0.60, green: 0.95, blue: 0.85, alpha: 1)),
        (SKColor(red: 0.61, green: 0.36, blue: 0.90, alpha: 1), SKColor(red: 0.85, green: 0.72, blue: 1.00, alpha: 1)),
        (SKColor(red: 0.95, green: 0.36, blue: 0.71, alpha: 1), SKColor(red: 1.00, green: 0.75, blue: 0.88, alpha: 1)),
        (SKColor(red: 0.30, green: 0.79, blue: 0.94, alpha: 1), SKColor(red: 0.75, green: 0.93, blue: 1.00, alpha: 1)),
        (SKColor(red: 0.56, green: 0.75, blue: 0.43, alpha: 1), SKColor(red: 0.86, green: 0.96, blue: 0.62, alpha: 1)),
        (SKColor(red: 0.37, green: 0.38, blue: 0.81, alpha: 1), SKColor(red: 0.66, green: 0.72, blue: 1.00, alpha: 1)),
        (SKColor(red: 0.50, green: 0.93, blue: 0.60, alpha: 1), SKColor(red: 0.20, green: 0.55, blue: 0.45, alpha: 1)),
        (SKColor(red: 0.80, green: 0.80, blue: 0.92, alpha: 1), SKColor(red: 0.45, green: 0.45, blue: 0.70, alpha: 1)),
    ]

    static func random(using rng: inout SeededGenerator) -> FishStyle {
        let colors = palette.randomElement(using: &rng)!
        return FishStyle(
            body: colors.body,
            accent: colors.accent,
            pattern: Pattern.allCases.randomElement(using: &rng)!,
            tail: Tail.allCases.randomElement(using: &rng)!,
            eyeScale: CGFloat.random(in: 0.85...1.25, using: &rng),
            hasDorsalFin: Bool.random(using: &rng)
        )
    }
}

/// A cartoony fish drawn at a fixed reference radius and scaled to any gameplay radius.
/// Faces +x; the rig is mirrored for left-facing fish.
final class FishNode: SKNode {
    static let referenceRadius: CGFloat = 30

    private let rig = SKNode()
    private let tail: SKShapeNode
    private let tailPhase: CGFloat
    private let mouthLine: SKShapeNode
    private let mouthGape: SKShapeNode

    init(style: FishStyle, isPlayer: Bool, tailPhase: CGFloat) {
        let R = FishNode.referenceRadius
        let outline = isPlayer ? SKColor.white : style.body.darkened(0.35)
        let lineWidth: CGFloat = isPlayer ? 3 : 2
        self.tailPhase = tailPhase

        let mouthPath = CGMutablePath()
        mouthPath.move(to: CGPoint(x: 1.32 * R, y: -0.1 * R))
        mouthPath.addQuadCurve(to: CGPoint(x: 1.0 * R, y: -0.25 * R), control: CGPoint(x: 1.2 * R, y: -0.28 * R))
        mouthLine = SKShapeNode(path: mouthPath)
        mouthLine.strokeColor = SKColor(white: 0.05, alpha: 0.8)
        mouthLine.lineWidth = 2.5
        mouthLine.lineCap = .round
        mouthLine.zPosition = 3

        // An open mouth is a jaw-like wedge cut into the nose, hinged at its inner point and
        // scaled vertically by how open it is.
        let gapePath = CGMutablePath()
        gapePath.move(to: .zero)
        gapePath.addLine(to: CGPoint(x: 0.68 * R, y: 0.26 * R))
        gapePath.addQuadCurve(to: CGPoint(x: 0.68 * R, y: -0.36 * R), control: CGPoint(x: 0.82 * R, y: -0.05 * R))
        gapePath.closeSubpath()
        mouthGape = SKShapeNode(path: gapePath)
        mouthGape.position = CGPoint(x: 0.74 * R, y: -0.14 * R)
        mouthGape.fillColor = SKColor(red: 0.18, green: 0.03, blue: 0.08, alpha: 1)
        mouthGape.strokeColor = outline
        mouthGape.lineWidth = lineWidth
        mouthGape.zPosition = 3
        mouthGape.isHidden = true
        let throat = SKShapeNode(ellipseOf: CGSize(width: 0.3 * R, height: 0.2 * R))
        throat.position = CGPoint(x: 0.42 * R, y: -0.08 * R)
        throat.fillColor = SKColor(red: 0.85, green: 0.35, blue: 0.45, alpha: 1)
        throat.strokeColor = .clear
        mouthGape.addChild(throat)

        tail = SKShapeNode(path: FishNode.tailPath(style.tail, R))
        tail.fillColor = style.accent
        tail.strokeColor = outline
        tail.lineWidth = lineWidth
        tail.position = CGPoint(x: -1.15 * R, y: 0)
        tail.zPosition = -2
        super.init()

        addChild(rig)
        rig.addChild(tail)

        if style.hasDorsalFin {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -0.55 * R, y: 0.75 * R))
            path.addQuadCurve(to: CGPoint(x: 0.35 * R, y: 0.8 * R), control: CGPoint(x: -0.4 * R, y: 1.45 * R))
            path.closeSubpath()
            let fin = SKShapeNode(path: path)
            fin.fillColor = style.accent
            fin.strokeColor = outline
            fin.lineWidth = lineWidth
            fin.zPosition = -1
            rig.addChild(fin)
        }

        let body = SKShapeNode(ellipseOf: CGSize(width: 2.7 * R, height: 1.9 * R))
        body.fillColor = style.body
        body.strokeColor = outline
        body.lineWidth = lineWidth
        rig.addChild(body)

        let belly = SKShapeNode(ellipseOf: CGSize(width: 1.8 * R, height: 0.7 * R))
        belly.position = CGPoint(x: 0.05 * R, y: -0.45 * R)
        belly.fillColor = SKColor(white: 1, alpha: 0.18)
        belly.strokeColor = .clear
        belly.zPosition = 0.5
        rig.addChild(belly)

        for mark in FishNode.patternNodes(style, R) {
            mark.zPosition = 1
            rig.addChild(mark)
        }

        let pectoral = SKShapeNode(ellipseOf: CGSize(width: 0.7 * R, height: 0.35 * R))
        pectoral.position = CGPoint(x: -0.15 * R, y: -0.2 * R)
        pectoral.zRotation = -0.4
        pectoral.fillColor = style.accent
        pectoral.strokeColor = outline
        pectoral.lineWidth = 1.5
        pectoral.zPosition = 2
        rig.addChild(pectoral)

        let eyeRadius = 0.26 * R * style.eyeScale
        let eye = SKShapeNode(circleOfRadius: eyeRadius)
        eye.position = CGPoint(x: 0.68 * R, y: 0.28 * R)
        eye.fillColor = .white
        eye.strokeColor = SKColor(white: 0, alpha: 0.35)
        eye.lineWidth = 1.5
        eye.zPosition = 3
        rig.addChild(eye)

        let pupil = SKShapeNode(circleOfRadius: eyeRadius * 0.5)
        pupil.position = CGPoint(x: eyeRadius * 0.35, y: 0)
        pupil.fillColor = SKColor(white: 0.08, alpha: 1)
        pupil.strokeColor = .clear
        eye.addChild(pupil)

        rig.addChild(mouthLine)
        rig.addChild(mouthGape)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// - Parameters:
    ///   - facing: -1...1; negative mirrors the fish to face left.
    ///   - stretchX/stretchY: squash-and-stretch multipliers.
    ///   - mouthOpen: 0 closed ... 1 wide open.
    func apply(radius: CGFloat, facing: CGFloat, tilt: CGFloat, stretchX: CGFloat, stretchY: CGFloat, mouthOpen: CGFloat, time: CGFloat, tailRate: CGFloat) {
        let s = radius / FishNode.referenceRadius
        let flip = (facing < 0 ? -1 : 1) * max(abs(facing), 0.05)
        rig.xScale = s * stretchX * flip
        rig.yScale = s * stretchY
        rig.zRotation = tilt
        tail.zRotation = sin(time * tailRate + tailPhase) * 0.28

        mouthGape.isHidden = mouthOpen < 0.03
        mouthGape.yScale = max(mouthOpen, 0.01)
        mouthGape.xScale = 0.8 + 0.2 * mouthOpen
        mouthLine.isHidden = mouthOpen > 0.3
    }

    private static func tailPath(_ tail: FishStyle.Tail, _ R: CGFloat) -> CGPath {
        let p = CGMutablePath()
        switch tail {
        case .fork:
            p.move(to: CGPoint(x: 0.15 * R, y: 0.2 * R))
            p.addLine(to: CGPoint(x: -0.75 * R, y: 0.72 * R))
            p.addLine(to: CGPoint(x: -0.5 * R, y: 0))
            p.addLine(to: CGPoint(x: -0.75 * R, y: -0.72 * R))
            p.addLine(to: CGPoint(x: 0.15 * R, y: -0.2 * R))
        case .fan:
            p.move(to: CGPoint(x: 0.15 * R, y: 0.2 * R))
            p.addQuadCurve(to: CGPoint(x: -0.7 * R, y: 0.75 * R), control: CGPoint(x: -0.3 * R, y: 0.3 * R))
            p.addQuadCurve(to: CGPoint(x: -0.7 * R, y: -0.75 * R), control: CGPoint(x: -1.05 * R, y: 0))
            p.addQuadCurve(to: CGPoint(x: 0.15 * R, y: -0.2 * R), control: CGPoint(x: -0.3 * R, y: -0.3 * R))
        case .point:
            p.move(to: CGPoint(x: 0.15 * R, y: 0.25 * R))
            p.addQuadCurve(to: CGPoint(x: -0.9 * R, y: 0.1 * R), control: CGPoint(x: -0.4 * R, y: 0.55 * R))
            p.addLine(to: CGPoint(x: -0.9 * R, y: -0.1 * R))
            p.addQuadCurve(to: CGPoint(x: 0.15 * R, y: -0.25 * R), control: CGPoint(x: -0.4 * R, y: -0.55 * R))
        }
        p.closeSubpath()
        return p
    }

    private static func patternNodes(_ style: FishStyle, _ R: CGFloat) -> [SKNode] {
        let color = style.accent.withAlphaComponent(0.6)
        switch style.pattern {
        case .plain:
            return []
        case .spots:
            let spots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
                (-0.7, 0.2, 0.17), (-0.3, 0.52, 0.13), (-0.25, -0.05, 0.15),
                (0.15, 0.42, 0.11), (0.25, -0.4, 0.12), (-0.75, -0.35, 0.11),
            ]
            return spots.map { spot in
                let node = SKShapeNode(circleOfRadius: spot.r * R)
                node.position = CGPoint(x: spot.x * R, y: spot.y * R)
                node.fillColor = color
                node.strokeColor = .clear
                return node
            }
        case .stripes:
            return [-0.75, -0.3, 0.15].map { (x: CGFloat) in
                // Keep each stripe inside the body ellipse.
                let halfHeight = 0.95 * R * sqrt(1 - pow(x / 1.35, 2)) * 0.9
                let width = 0.2 * R
                let node = SKShapeNode(rect: CGRect(x: -width / 2, y: -halfHeight, width: width, height: halfHeight * 2), cornerRadius: width / 2)
                node.position = CGPoint(x: x * R, y: 0)
                node.fillColor = color
                node.strokeColor = .clear
                return node
            }
        }
    }
}

extension SKColor {
    func darkened(_ amount: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = 1 - amount
        return SKColor(red: r * k, green: g * k, blue: b * k, alpha: a)
    }
}
