import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import BiggerFish

/// Bigger Fish on an iPad (`ScreenFit`): the game plays at the playfield's size wherever it is, every phone keeps its
/// menus as they were, and a bigger screen grows them to fit.
struct ScreenFitTests {
    /// Every iPhone screen in landscape (and with its safe area taken off), from an iPhone SE to a Pro Max.
    static let phones = [CGSize(width: 667, height: 375), CGSize(width: 812, height: 375), CGSize(width: 844, height: 390),
                         CGSize(width: 852, height: 393), CGSize(width: 874, height: 402), CGSize(width: 896, height: 414),
                         CGSize(width: 912, height: 420), CGSize(width: 926, height: 428), CGSize(width: 932, height: 430),
                         CGSize(width: 956, height: 440), CGSize(width: 862, height: 419), CGSize(width: 750, height: 369)]
    /// iPads in landscape: mini, 11-inch, 13-inch, and an older 9.7-inch; full screen, and less their home indicator.
    static let iPads = [CGSize(width: 1133, height: 744), CGSize(width: 1210, height: 834), CGSize(width: 1376, height: 1032),
                        CGSize(width: 1024, height: 768), CGSize(width: 1210, height: 814), CGSize(width: 1376, height: 1012)]

    @Test func phonesKeepTheirMenusAsTheyWere() {
        for phone in Self.phones {
            #expect(ScreenFit.menuScale(for: phone) == 1, "\(phone)")
            #expect(ScreenFit.tallness(of: phone) == 1, "\(phone)")
        }
    }

    @Test func aBiggerScreenGrowsTheMenusAsMuchAsFits() {
        for iPad in Self.iPads {
            let scale = ScreenFit.menuScale(for: iPad)
            #expect(scale > 1, "\(iPad)")
            // Laid out at least a phone's size both ways, and exactly as wide or as tall as the biggest phone.
            let laidOut = CGSize(width: iPad.width / scale, height: iPad.height / scale)
            #expect(laidOut.width >= ScreenFit.largestPhone.width - 1e-9 && laidOut.height >= ScreenFit.largestPhone.height - 1e-9)
            #expect(abs(laidOut.width - ScreenFit.largestPhone.width) < 1e-9 || abs(laidOut.height - ScreenFit.largestPhone.height) < 1e-9)
            let taller = ScreenFit.tallness(of: laidOut)
            #expect(taller > 1 && taller <= 1.3, "\(iPad)")
        }
        // A window narrower than a phone's (Split View, Stage Manager) keeps the phone's menus.
        #expect(ScreenFit.menuScale(for: CGSize(width: 694, height: 834)) == 1)
        #expect(ScreenFit.menuScale(for: .zero) == 1)
    }

    @Test func thePlayfieldFillsTheWidthOfAnIPadBetweenEqualBands() {
        for iPad in Self.iPads {
            let field = ScreenFit.playfieldFrame(in: iPad)
            #expect(abs(field.width - iPad.width) < 1e-9, "\(iPad)")
            #expect(abs(field.width / field.height - GameTuning.playfieldSize.width / GameTuning.playfieldSize.height) < 1e-9)
            #expect(field.minY > 0 && abs(field.minY - (iPad.height - field.maxY)) < 1e-9, "\(iPad)")
        }
        let phone = ScreenFit.playfieldFrame(in: GameTuning.playfieldSize)
        #expect(phone == CGRect(origin: .zero, size: GameTuning.playfieldSize))
    }

    /// "Hold anywhere": on an iPad, a touch in a band above or below the playfield goes to the scene, as on the
    /// playfield, and the scene still plays at its own size.
    @MainActor @Test func aTouchInABandReachesTheScene() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let container = PlayfieldView.Container(frame: CGRect(x: 0, y: 0, width: 1210, height: 834))
        container.sceneView.presentScene(scene)
        container.layoutIfNeeded()
        let field = container.sceneView.frame
        #expect(field.minX == 0 && field.width == 1210)
        #expect(field.minY > 100 && 834 - field.maxY > 100)
        for point in [CGPoint(x: 600, y: 20), CGPoint(x: 10, y: 820), CGPoint(x: 600, y: 417), CGPoint(x: 1200, y: field.minY - 1)] {
            #expect(container.hitTest(point, with: nil) === container.sceneView, "\(point)")
        }
        #expect(container.hitTest(CGPoint(x: 600, y: 900), with: nil) == nil)
        #expect(scene.size == GameTuning.playfieldSize)
        withExtendedLifetime(scene) {}
    }

    /// An iPhone Duo's screens in landscape, closed and open.
    private static let duo = (closed: CGRect(x: 0, y: 0, width: 678, height: 466), open: CGRect(x: 0, y: 0, width: 951, height: 669))

    /// Opening or closing an iPhone Duo resizes the screen under a level: a run in play pauses, as when the app is
    /// interrupted. The first layout doesn't count, and the paused level stays paused.
    @MainActor @Test func aRunPausesWhenTheScreenChangesSize() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let container = PlayfieldView.Container(frame: Self.duo.closed)
        container.sceneView.presentScene(scene)
        scene.debugStart()
        container.layoutIfNeeded()
        #expect(scene.debugPhase == .playing)

        container.frame = Self.duo.open
        container.layoutIfNeeded()
        #expect(scene.debugPhase == .paused)
        container.frame = Self.duo.closed
        container.layoutIfNeeded()
        #expect(scene.debugPhase == .paused)
        withExtendedLifetime(scene) {}
    }

    /// A level waiting on its card isn't running, so a resize leaves it waiting.
    @MainActor @Test func aLevelNotYetStartedStaysOnItsCard() {
        let scene = GameScene(world: .shallowReef, levelIndex: 0)
        let container = PlayfieldView.Container(frame: Self.duo.closed)
        container.sceneView.presentScene(scene)
        container.layoutIfNeeded()
        #expect(scene.debugPhase == .ready)

        container.frame = Self.duo.open
        container.layoutIfNeeded()
        #expect(scene.debugPhase == .ready)
        withExtendedLifetime(scene) {}
    }

    /// The map art draws at the screen's own resolution times the menus' scale, and follows the screen's resolution when
    /// it changes, as an iPhone Duo's can between its two screens.
    @MainActor @Test func theMapArtFollowsTheScreensResolution() {
        let view = MapArtView.ScaledView(frame: CGRect(x: 0, y: 0, width: 300, height: 150))
        // Another screen's resolution than the one the view started on.
        let other: CGFloat = view.traitCollection.displayScale == 3 ? 2 : 3
        view.traitOverrides.displayScale = other
        view.updateTraitsIfNeeded()
        #expect(view.contentScaleFactor == other)
        view.menuScale = 1.5
        #expect(view.contentScaleFactor == other * 1.5)
    }

    /// Recording or mirroring the screen drops the game to 60 frames a second, so neither it nor the recording stutters,
    /// and stopping goes back to 120.
    @MainActor @Test func recordingTheScreenDrawsAt60() {
        let container = PlayfieldView.Container(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        #expect(container.sceneView.preferredFramesPerSecond == 120)
        container.traitOverrides.sceneCaptureState = .active
        container.updateTraitsIfNeeded()
        #expect(container.sceneView.preferredFramesPerSecond == 60)
        container.traitOverrides.sceneCaptureState = .inactive
        container.updateTraitsIfNeeded()
        #expect(container.sceneView.preferredFramesPerSecond == 120)
    }
}
