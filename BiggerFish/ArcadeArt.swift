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

    /// Kelp Forest's water: sunlit green-teal fading to a deep green.
    static func kelpWater() -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 256))
        let image = renderer.image { context in
            let colors = [UIColor(red: 0.2, green: 0.5, blue: 0.43, alpha: 1).cgColor,
                          UIColor(red: 0.03, green: 0.13, blue: 0.12, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                      locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
        return SKTexture(image: image)
    }
}
