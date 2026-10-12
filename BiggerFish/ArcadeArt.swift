import SpriteKit
import UIKit

/// Arcade-specific visuals live here until the shared art consolidation after Math Reef's release.
enum ArcadeArt {
    /// Jelly Bloom's water, top to bottom (the bands around the playfield on an iPad carry it on).
    static func bloomWaterColors(night: Bool) -> (top: UIColor, bottom: UIColor) {
        night
            ? (UIColor(red: 0.16, green: 0.09, blue: 0.31, alpha: 1), UIColor(red: 0.015, green: 0.025, blue: 0.09, alpha: 1))
            : (UIColor(red: 0.31, green: 0.19, blue: 0.53, alpha: 1), UIColor(red: 0.035, green: 0.07, blue: 0.19, alpha: 1))
    }

    static func bloomWater(night: Bool) -> SKTexture {
        let colors = bloomWaterColors(night: night)
        return water(top: colors.top, bottom: colors.bottom)
    }

    /// Kelp Forest's water: sunlit green-teal fading to a deep green.
    static let kelpWaterColors = (top: UIColor(red: 0.2, green: 0.5, blue: 0.43, alpha: 1),
                                  bottom: UIColor(red: 0.03, green: 0.13, blue: 0.12, alpha: 1))

    static func kelpWater() -> SKTexture {
        water(top: kelpWaterColors.top, bottom: kelpWaterColors.bottom)
    }

    /// Sunset Cove's water: coral and pink at the surface, through magenta, to deep purple at the bottom.
    static let sunsetWaterColors = (top: UIColor(red: 0.98, green: 0.55, blue: 0.5, alpha: 1),
                                    middle: UIColor(red: 0.72, green: 0.24, blue: 0.5, alpha: 1),
                                    bottom: UIColor(red: 0.16, green: 0.05, blue: 0.27, alpha: 1))

    static func sunsetWater() -> SKTexture {
        water(colors: [sunsetWaterColors.top, UIColor(red: 0.9, green: 0.4, blue: 0.52, alpha: 1), sunsetWaterColors.middle,
                       sunsetWaterColors.bottom], locations: [0, 0.22, 0.55, 1])
    }

    /// A soft round glow, white at its heart and fading to nothing at its edge, for tinting (the sun and its haze).
    static let glow: SKTexture = {
        let side: CGFloat = 128
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.45).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 1])!
            let center = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                                 endRadius: side / 2, options: [])
        }
        return SKTexture(image: image)
    }()

    /// A shaft of light: a long narrow wedge, brightest where it enters at the top and fading as it goes down, for
    /// tinting. Its anchor is the middle of its top edge.
    static let lightShaft: SKTexture = {
        let size = CGSize(width: 64, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let wedge = CGMutablePath()
            wedge.move(to: CGPoint(x: size.width * 0.38, y: 0))
            wedge.addLine(to: CGPoint(x: size.width * 0.62, y: 0))
            wedge.addLine(to: CGPoint(x: size.width, y: size.height))
            wedge.addLine(to: CGPoint(x: 0, y: size.height))
            wedge.closeSubpath()
            cg.addPath(wedge)
            cg.clip()
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.35).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }()

    private static func water(top: UIColor, bottom: UIColor) -> SKTexture {
        water(colors: [top, bottom], locations: [0, 1])
    }

    private static func water(colors: [UIColor], locations: [CGFloat]) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 256))
        let image = renderer.image { context in
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray,
                                      locations: locations)!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
        return SKTexture(image: image)
    }
}
