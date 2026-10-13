import SpriteKit
import SwiftUI

// Bigger Fish on screens bigger than a phone's (an iPad). The game itself never changes size: its scenes play at
// `GameTuning.playfieldSize`, fitted to the screen, so on an iPad the playfield fills the width with a band of its
// water above and below. The menus are laid out as on the biggest phone and grown to fill the screen, so an iPad
// shows the same screens bigger rather than small in the middle of a lot of water.

enum ScreenFit {
    /// The biggest phone screen the menus were laid out for: an iPhone Pro Max's, in landscape.
    static let largestPhone = CGSize(width: 956, height: 440)

    /// How much bigger the menus draw on a screen of `size`: 1 on every phone, and on a bigger screen as much bigger
    /// as fits both ways.
    static func menuScale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return max(1, min(size.width / largestPhone.width, size.height / largestPhone.height))
    }

    /// How many times taller than the tallest phone's a screen of `size` (in a menu's own points, `ScreenScaled`) is,
    /// up to 1.3: 1 on every phone. A menu on an iPad, less wide for its height than a phone, can grow its pictures a
    /// little by it.
    static func tallness(of size: CGSize) -> CGFloat {
        min(max(1, size.height / largestPhone.height), 1.3)
    }

    /// Where the playfield sits on a screen of `size`: fitted (`GameTuning.fittedPlayfieldSize`) and centered.
    static func playfieldFrame(in size: CGSize) -> CGRect {
        let fitted = GameTuning.fittedPlayfieldSize(in: size)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }
}

extension EnvironmentValues {
    /// `ScreenFit.menuScale` for the screen a view is on: 1 on a phone.
    @Entry var menuScale: CGFloat = 1
}

/// A menu screen laid out at a phone's size and scaled up to fill a bigger screen (`ScreenFit.menuScale`). `content`
/// gets the size to lay out in, and the safe area's insets, both in its own (unscaled) points. On a phone it's the
/// screen as it is. Backgrounds that run to the screen's edges go outside it, unscaled.
struct ScreenScaled<Content: View>: View {
    @ViewBuilder let content: (_ size: CGSize, _ safeArea: EdgeInsets) -> Content

    var body: some View {
        GeometryReader { geometry in
            let scale = ScreenFit.menuScale(for: geometry.size)
            let size = CGSize(width: geometry.size.width / scale, height: geometry.size.height / scale)
            let insets = geometry.safeAreaInsets
            content(size, EdgeInsets(top: insets.top / scale, leading: insets.leading / scale,
                                     bottom: insets.bottom / scale, trailing: insets.trailing / scale))
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .environment(\.menuScale, scale)
        }
    }
}

/// A scene played at the playfield's size (a level, the tutorial, the credits), fitted to the screen with its world's
/// water in any band above and below. A touch anywhere on the screen reaches the scene, bands included, so "hold
/// anywhere" means anywhere.
struct PlayfieldScreen: View {
    let scene: SKScene
    let water: PlayfieldWater
    /// The scene's pause menu is up: the bands darken with it.
    var paused = false

    var body: some View {
        ZStack {
            PlayfieldBands(water: water, paused: paused)
            PlayfieldView(scene: scene).id(ObjectIdentifier(scene))
        }
        .ignoresSafeArea()
    }
}

/// The colors at the top and bottom of a world's water, as its scenes paint them, for the bands around the playfield.
struct PlayfieldWater: Equatable {
    let top: Color
    let bottom: Color

    /// `WaterTextures.gradient()`'s ends (FishKit): Shallow Reef, the tutorial, and the credits.
    static let reef = PlayfieldWater(top: Color(red: 0.20, green: 0.62, blue: 0.80), bottom: Color(red: 0.03, green: 0.12, blue: 0.30))
    /// `ArcadeArt.kelpWater()`'s.
    static let kelp = PlayfieldWater(top: Color(uiColor: ArcadeArt.kelpWaterColors.top), bottom: Color(uiColor: ArcadeArt.kelpWaterColors.bottom))
    /// Midnight Zone's dark, which covers its water everywhere but your headlamp's beam.
    static let midnight = PlayfieldWater(top: Color(uiColor: GameTuning.midnightDark), bottom: Color(uiColor: GameTuning.midnightDark))
    /// `ArcadeArt.sunsetWater()`'s: coral at the surface, deep purple at the bottom.
    static let sunset = PlayfieldWater(top: Color(uiColor: ArcadeArt.sunsetWaterColors.top),
                                       bottom: Color(uiColor: ArcadeArt.sunsetWaterColors.bottom))

    /// `ArcadeArt.bloomWater(night: true)`'s: for every Jelly Bloom level, as a level can turn to night without leaving
    /// the scene ("Next level"), and the bands should stay darker than the water either way.
    static let bloom: PlayfieldWater = {
        let colors = ArcadeArt.bloomWaterColors(night: true)
        return PlayfieldWater(top: Color(uiColor: colors.top), bottom: Color(uiColor: colors.bottom))
    }()

    /// A world's water.
    static func of(_ world: ArcadeWorld) -> PlayfieldWater {
        switch world {
        case .shallowReef: .reef
        case .jellyBloom: .bloom
        case .kelpForest: .kelp
        case .midnightZone: .midnight
        case .sunsetCove: .sunset
        case .riptideReef: .reef
        }
    }
}

/// Above and below the playfield, where the screen is taller than it (an iPad): its water carried on past its edges,
/// darker, and darker still toward the screen's edge, so the screen reads as one sea while the water you can swim in
/// stands out.
struct PlayfieldBands: View {
    let water: PlayfieldWater
    /// Under the pause menu, whose backdrop (`MenuBackdrop`) runs from Settings' night blue at the playfield's top to
    /// its abyss at the bottom: the bands carry those on, so the menu fills the screen.
    var paused = false
    /// How much of the water's color the bands keep beside the playfield, and at the screen's edge.
    static let brightness: (field: Double, edge: Double) = (0.55, 0.3)

    var body: some View {
        GeometryReader { geometry in
            let field = ScreenFit.playfieldFrame(in: geometry.size)
            VStack(spacing: 0) {
                band(water.top, fieldAt: .bottom, paused: DeepEndColors.night).frame(height: max(0, field.minY))
                Spacer(minLength: 0)
                band(water.bottom, fieldAt: .top, paused: DeepEndColors.abyss)
                    .frame(height: max(0, geometry.size.height - field.maxY))
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func band(_ color: Color, fieldAt side: UnitPoint, paused menu: Color) -> some View {
        LinearGradient(colors: [color.opacity(Self.brightness.edge), color.opacity(Self.brightness.field)],
                       startPoint: side == .top ? .bottom : .top, endPoint: side)
            .overlay(menu.opacity(paused ? MenuBackdrop.opacity : 0))
    }
}

/// The SpriteKit view under `PlayfieldScreen`: the scene's view sized to the fitted playfield, inside a view the
/// size of the screen that hands it every touch.
struct PlayfieldView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> Container {
        let container = Container()
        container.sceneView.ignoresSiblingOrder = true
        container.sceneView.presentScene(scene)
        return container
    }

    func updateUIView(_ container: Container, context: Context) {
        if container.sceneView.scene !== scene { container.sceneView.presentScene(scene) }
    }

    final class Container: UIView {
        let sceneView = SKView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            addSubview(sceneView)
            matchScreenCapture()
            registerForTraitChanges([UITraitSceneCaptureState.self]) { (container: Container, _: UITraitCollection) in
                container.matchScreenCapture()
            }
        }

        /// The game draws at up to 120 frames a second, but at 60 while the screen is recorded or mirrored: the phone
        /// can't draw at 120 and encode the video too, so both the game and the recording stuttered (Kraig's own
        /// footage did, until he turned on Limit Frame Rate). Back to 120 when the recording stops.
        static func framesPerSecond(capturing: Bool) -> Int { capturing ? 60 : 120 }

        private func matchScreenCapture() {
            sceneView.preferredFramesPerSecond = Self.framesPerSecond(capturing: traitCollection.sceneCaptureState == .active)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// The fitted playfield, its edges on the screen's pixels (as SwiftUI lays out), so the game draws sharp.
        override func layoutSubviews() {
            super.layoutSubviews()
            let field = ScreenFit.playfieldFrame(in: bounds.size)
            let pixels = max(1, traitCollection.displayScale)
            func snap(_ value: CGFloat) -> CGFloat { (value * pixels).rounded() / pixels }
            let left = snap(field.minX), top = snap(field.minY)
            sceneView.frame = CGRect(x: left, y: top, width: snap(field.maxX) - left, height: snap(field.maxY) - top)
        }

        /// A touch in a band goes to the scene, as a touch just past the playfield's edge.
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            return hit === self ? sceneView : hit
        }
    }
}
