import SpriteKit
import UIKit

/// Background textures shared by both apps.
public enum WaterTextures {
    public static func gradient() -> SKTexture {
        let size = CGSize(width: 4, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [
                UIColor(red: 0.20, green: 0.62, blue: 0.80, alpha: 1).cgColor,
                UIColor(red: 0.08, green: 0.35, blue: 0.60, alpha: 1).cgColor,
                UIColor(red: 0.03, green: 0.12, blue: 0.30, alpha: 1).cgColor,
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }

    public static func dot() -> SKTexture {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return SKTexture(image: image)
    }
}
