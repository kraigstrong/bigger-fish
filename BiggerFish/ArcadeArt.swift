import SpriteKit
import UIKit

/// Arcade-specific visuals live here until the shared art consolidation after Math Reef's release.
enum ArcadeArt {
    static func bloomWater(night: Bool) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 256))
        let image = renderer.image { context in
            let colors = night
                ? [UIColor(red: 0.16, green: 0.09, blue: 0.31, alpha: 1).cgColor,
                   UIColor(red: 0.015, green: 0.025, blue: 0.09, alpha: 1).cgColor]
                : [UIColor(red: 0.31, green: 0.19, blue: 0.53, alpha: 1).cgColor,
                   UIColor(red: 0.035, green: 0.07, blue: 0.19, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                      locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
        return SKTexture(image: image)
    }

    static func urchin(radius: CGFloat) -> SKNode {
        let node = SKNode()
        let spikes = CGMutablePath()
        for i in 0..<24 {
            let angle = CGFloat(i) * .pi / 12
            let r = radius * (i.isMultiple(of: 2) ? 1 : 0.6)
            let p = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if i == 0 { spikes.move(to: p) } else { spikes.addLine(to: p) }
        }
        spikes.closeSubpath()
        let body = SKShapeNode(path: spikes)
        body.fillColor = SKColor(red: 0.44, green: 0.18, blue: 0.46, alpha: 1)
        body.strokeColor = SKColor(red: 1, green: 0.53, blue: 0.7, alpha: 1)
        body.lineWidth = 1.5
        node.addChild(body)
        return node
    }
}
