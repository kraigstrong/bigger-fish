import CoreGraphics

/// Math Reef's map geometry, independent of level IDs, unlocks and rewards.
public enum OceanMapLayout {
    public static let levelSpacing: CGFloat = 118
    public static let levelStartX: CGFloat = 110

    public static func worldCenters(count: Int, size: CGSize) -> [CGPoint] {
        let left: CGFloat = 106, right = size.width - 156
        return (0..<max(0, count)).map { index in
            CGPoint(x: count > 1 ? left + (right - left) * CGFloat(index) / CGFloat(count - 1) : size.width / 2,
                    y: size.height * (index.isMultiple(of: 2) ? 0.60 : 0.38))
        }
    }

    public static func levelCenters(count: Int, height: CGFloat) -> [CGPoint] {
        (0..<max(0, count)).map { index in
            CGPoint(x: levelStartX + levelSpacing * CGFloat(index),
                    y: height * 0.44 + sin(CGFloat(index) * 1.1) * height * 0.16)
        }
    }

    public static func levelContentWidth(count: Int) -> CGFloat {
        levelStartX * 2 + levelSpacing * CGFloat(max(0, count - 1))
    }
}
