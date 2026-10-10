import SpriteKit
import UIKit

/// The tutorial's finger, as in Math Reef's: it presses on open water, well away from your fish, for "hold" (anywhere
/// means anywhere), and lifts off with a pop for "let go", with arrows by your fish pointing the way it'll go.
final class TutorialHint: SKNode {
    enum Step { case hold, letGo }

    private let spot: CGPoint
    private let hand = SKNode()
    /// Under the fingertip while it presses.
    private let touchSpot = SKShapeNode(circleOfRadius: 24)
    private let arrows = SKNode()
    private var arrowsUp = true

    init(spot: CGPoint) {
        self.spot = spot
        super.init()
        // The symbol's fingertip is near its top-left corner; anchor it there.
        let tip = CGPoint(x: 0.22, y: 0.92)
        if let finger = Self.symbol("hand.point.up.left.fill", pointSize: 80),
           let shade = Self.symbol("hand.point.up.left.fill", pointSize: 80, color: UIColor(white: 0, alpha: 0.35)) {
            finger.anchorPoint = tip
            shade.anchorPoint = tip
            shade.position = CGPoint(x: 3, y: -3)
            finger.zPosition = 0.5
            hand.addChild(shade)
            hand.addChild(finger)
        }
        hand.position = spot
        hand.zPosition = 2
        hand.alpha = 0
        addChild(hand)

        touchSpot.fillColor = SKColor(white: 1, alpha: 0.28)
        touchSpot.strokeColor = SKColor(white: 1, alpha: 0.85)
        touchSpot.lineWidth = 3
        touchSpot.position = spot
        touchSpot.zPosition = 1
        touchSpot.alpha = 0
        addChild(touchSpot)

        let bob = SKNode()
        for i in 0..<2 {
            guard let chevron = Self.symbol("chevron.up", pointSize: 22, weight: .heavy) else { continue }
            chevron.position = CGPoint(x: 0, y: CGFloat(i) * 12)
            chevron.alpha = i == 0 ? 0.45 : 0.9
            bob.addChild(chevron)
        }
        let nudge = SKAction.moveBy(x: 0, y: 7, duration: 0.4)
        nudge.timingMode = .easeInEaseOut
        bob.run(.repeatForever(.sequence([nudge, nudge.reversed()])))
        arrows.addChild(bob)
        arrows.alpha = 0
        addChild(arrows)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ step: Step) {
        switch step {
        case .hold: press()
        case .letGo: liftOff()
        }
        arrowsUp = step == .hold
        arrows.zRotation = arrowsUp ? 0 : .pi
        arrows.removeAllActions()
        arrows.run(.fadeIn(withDuration: 0.25))
    }

    func hide() {
        hand.removeAllActions()
        touchSpot.removeAllActions()
        arrows.removeAllActions()
        for node in [hand, touchSpot, arrows] { node.run(.fadeOut(withDuration: 0.2)) }
    }

    /// Keeps the arrows by your fish (its center and radius on screen), above it to rise and below it to fall.
    func follow(fish: CGPoint, radius: CGFloat) {
        arrows.position = CGPoint(x: fish.x, y: fish.y + (arrowsUp ? 1 : -1) * (radius + 24))
    }

    /// The finger comes down on the water and stays pressed, pulsing, with a touch ring under it.
    private func press() {
        hand.removeAllActions()
        touchSpot.removeAllActions()
        hand.position = spot
        hand.alpha = 0
        hand.setScale(1.25)
        touchSpot.alpha = 0
        touchSpot.setScale(0.4)
        let down = SKAction.group([.fadeIn(withDuration: 0.2), .scale(to: 0.92, duration: 0.3)])
        down.timingMode = .easeIn
        hand.run(.sequence([
            down,
            .run { [weak self] in self?.touchDown() },
            .repeatForever(.sequence([.scale(to: 0.84, duration: 0.45), .scale(to: 0.92, duration: 0.45)])),
        ]))
    }

    private func touchDown() {
        touchSpot.run(.sequence([
            .group([.fadeIn(withDuration: 0.1), .scale(to: 1, duration: 0.12)]),
            .repeatForever(.sequence([.scale(to: 1.3, duration: 0.45), .scale(to: 1, duration: 0.45)])),
        ]))
        let ripple = SKShapeNode(circleOfRadius: 24)
        ripple.strokeColor = .white
        ripple.lineWidth = 3
        ripple.position = spot
        ripple.zPosition = 1
        addChild(ripple)
        ripple.run(.sequence([.group([.scale(to: 2.4, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
    }

    /// The finger lifts off the water with a pop. If it isn't down already (a replay), it presses first.
    private func liftOff() {
        hand.removeAllActions()
        touchSpot.removeAllActions()
        var steps: [SKAction] = []
        if hand.alpha < 0.5 {
            hand.position = spot
            hand.setScale(1.25)
            steps += [
                .group([.fadeIn(withDuration: 0.15), .scale(to: 0.88, duration: 0.2)]),
                .run { [weak self] in
                    self?.touchSpot.alpha = 1
                    self?.touchSpot.setScale(1)
                },
                .wait(forDuration: 0.5),
            ]
        } else {
            steps.append(.scale(to: 0.84, duration: 0.15))
        }
        let lift = SKAction.group([
            .move(by: CGVector(dx: 12, dy: 34), duration: 0.35),
            .scale(to: 1.25, duration: 0.35),
            .sequence([.wait(forDuration: 0.15), .fadeOut(withDuration: 0.2)]),
        ])
        lift.timingMode = .easeOut
        steps += [.run { [weak self] in self?.pop() }, lift]
        hand.run(.sequence(steps))
    }

    /// The touch ring bursts into droplets as the finger leaves the water.
    private func pop() {
        touchSpot.removeAllActions()
        touchSpot.alpha = 1
        touchSpot.run(.group([.scale(to: 1.9, duration: 0.2), .fadeOut(withDuration: 0.2)]))
        for i in 0..<8 {
            let angle = CGFloat(i) / 8 * 2 * .pi
            let drop = SKShapeNode(circleOfRadius: 3.5)
            drop.fillColor = .white
            drop.strokeColor = .clear
            drop.position = spot
            drop.zPosition = 1
            addChild(drop)
            let fly = SKAction.move(by: CGVector(dx: cos(angle) * 46, dy: sin(angle) * 46), duration: 0.32)
            fly.timingMode = .easeOut
            drop.run(.sequence([
                .group([fly, .sequence([.wait(forDuration: 0.12), .fadeOut(withDuration: 0.2)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// An SF Symbol as a sprite, drawn in `color`.
    private static func symbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .regular,
                               color: UIColor = .white) -> SKSpriteNode? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let drawn = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
        return SKSpriteNode(texture: SKTexture(image: drawn))
    }
}
