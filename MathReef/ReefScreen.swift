import SpriteKit
import SwiftUI

// Math Reef on screens bigger than a phone's (an iPad), after Bigger Fish's `ScreenFit`. The whole app is one scene,
// and on an iPad it's laid out as on the biggest phone, only taller, and drawn bigger to fill the screen: the maps
// and cards spread into the extra height, while a round plays in a band of water as tall as that phone's, with
// darker water above and below. So a round plays the same on every screen: the same lanes, the same reach.

enum ReefScreen {
    /// The biggest phone screen the app was laid out for: an iPhone Pro Max's, in landscape.
    static let largestPhone = CGSize(width: 956, height: 440)

    /// How much bigger the scene draws on a screen of `size`: 1 on every phone, and on a bigger screen as much bigger
    /// as fits both ways.
    static func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return max(1, min(size.width / largestPhone.width, size.height / largestPhone.height))
    }

    /// The water a round plays in, in a scene of `size`: all of it on a phone, and on a taller screen a band across
    /// the middle as tall as the biggest phone's.
    static func playfield(in size: CGSize) -> CGRect {
        let height = min(size.height, largestPhone.height)
        return CGRect(x: 0, y: ((size.height - height) / 2).rounded(), width: size.width, height: height)
    }

    /// `WaterTextures.gradient()`'s ends (FishKit), which the bands above and below the playfield carry on.
    static let waterTop = UIColor(red: 0.20, green: 0.62, blue: 0.80, alpha: 1)
    static let waterBottom = UIColor(red: 0.03, green: 0.12, blue: 0.30, alpha: 1)

    /// A band's texture: `color`, darkened (`ReefTuning.bandBrightness`), and darker still away from the playfield,
    /// which is at its bottom for the band above (`fieldBelow`) and at its top for the band below.
    static func bandTexture(_ color: UIColor, fieldBelow: Bool) -> SKTexture {
        func shade(_ brightness: CGFloat) -> CGColor {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r * brightness, green: g * brightness, blue: b * brightness, alpha: 1).cgColor
        }
        let size = CGSize(width: 4, height: 64)
        let edge = shade(ReefTuning.bandBrightness.edge), field = shade(ReefTuning.bandBrightness.field)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            // The image's top is the band's top.
            let colors = (fieldBelow ? [edge, field] : [field, edge]) as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }
}

/// How much further in from the left and right edges than on a phone the controls in the top corners sit (the maps'
/// titles and back button, the close and settings buttons, a round's progress, the tutorial's Skip), to clear hardware
/// covering a top corner: a closed iPhone Duo's camera. Both are 0 everywhere else, as a Dynamic Island sits at the
/// middle of the edge, below them.
struct ReefCorners: Equatable {
    var left: CGFloat = 0
    var right: CGFloat = 0

    /// On a phone, the top-left controls start this far in from the left edge (the back button's side, its center 46 in),
    /// the top-right ones end this far in from the right (the settings button's side, its center 64 in), and none reaches
    /// further down from the top than `depth`.
    static let phoneLeft: CGFloat = 26, phoneRight: CGFloat = 44, depth: CGFloat = 64
    /// Room left between a control and the hardware.
    static let gap: CGFloat = 10

    init() {}

    /// The corners on a screen of `size` (the scene's points) where `occlusions` (the same) are covered.
    init(size: CGSize, occlusions: [CGRect]) {
        for covered in occlusions where covered.maxY > size.height - Self.depth {
            if covered.midX < size.width / 2 {
                left = max(left, covered.maxX + Self.gap - Self.phoneLeft)
            } else {
                right = max(right, size.width - Self.phoneRight - (covered.minX - Self.gap))
            }
        }
    }
}

/// The scene's view. On a phone it's the screen as it is. On a bigger screen the scene is laid out at the screen's
/// size over `ReefScreen.scale` and drawn that much bigger, at the screen's own resolution so it stays sharp: a SwiftUI
/// scale effect would only stretch what it drew at a phone's size. Touches land in the scene's own points either way.
struct ReefView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> Container {
        let container = Container()
        container.scene = scene
        return container
    }

    func updateUIView(_ container: Container, context: Context) {
        container.scene = scene
    }

    final class Container: UIView {
        let sceneView = SKView()
        /// Holds the scene's view at the scene's size, and draws it bigger. The scene's view itself is never
        /// transformed: one that was drew at the wrong shape on an iPad.
        private let scaler = UIView()
        var scene: SKScene? { didSet { setNeedsLayout() } }

        override init(frame: CGRect) {
            super.init(frame: frame)
            sceneView.ignoresSiblingOrder = true
            sceneView.preferredFramesPerSecond = 120
            scaler.addSubview(sceneView)
            addSubview(scaler)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
        }

        /// Turning a closed iPhone Duo around moves its camera to the other corner, and the safe area with it.
        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            setNeedsLayout()
        }

        /// The parts of the screen hardware covers, in the scene's points: a closed iPhone Duo's camera, in a corner. Only
        /// an app built with the iOS 27.1 SDK fills the iPhone Duo's screens to their edges, and only that SDK can say where
        /// its camera is; an older SDK's app has a window clear of it.
        private var occlusions: [CGRect] {
            // The iOS 27.1 SDK's UIKit, the first with reserved regions.
            #if canImport(UIKit, _version: 9127.0.85)
            if #available(iOS 27.1, *) {
                let scale = ReefScreen.scale(for: bounds.size)
                return reservedRegions(kind: .occlusion).map { region in
                    // UIKit's y runs down the screen, the scene's up it.
                    let frame = region.frame
                    return CGRect(x: frame.minX / scale, y: (bounds.height - frame.maxY) / scale,
                                  width: frame.width / scale, height: frame.height / scale)
                }
            }
            #endif
            return []
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0 else { return }
            (scene as? PracticeScene)?.occlusions = occlusions
            let scale = ReefScreen.scale(for: bounds.size)
            scaler.bounds = CGRect(x: 0, y: 0, width: bounds.width / scale, height: bounds.height / scale)
            scaler.center = CGPoint(x: bounds.midX, y: bounds.midY)
            scaler.transform = CGAffineTransform(scaleX: scale, y: scale)
            sceneView.frame = scaler.bounds
            let screenScale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
            if screenScale > 0 { sceneView.contentScaleFactor = screenScale * scale }
            // Only once the view has a size: a scene presented in a view with none is sized to nothing, and never builds.
            if let scene, sceneView.scene !== scene { sceneView.presentScene(scene) }
        }
    }
}
