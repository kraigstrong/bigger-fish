import CoreGraphics
import Testing
import UIKit
@testable import MathReef

/// Phones draw as they always have; an iPad draws the scene bigger, and plays a round in water the biggest phone's size.
struct ReefScreenTests {
    /// Landscape screens, in points: iPhone SE, 16e, 17, 17 Pro Max.
    private let phones = [CGSize(width: 667, height: 375), CGSize(width: 844, height: 390),
                          CGSize(width: 874, height: 402), CGSize(width: 956, height: 440)]
    /// iPad mini, 11-inch, 13-inch.
    private let iPads = [CGSize(width: 1133, height: 744), CGSize(width: 1180, height: 820),
                         CGSize(width: 1376, height: 1032)]

    private func scene(on screen: CGSize) -> CGSize {
        let scale = ReefScreen.scale(for: screen)
        return CGSize(width: screen.width / scale, height: screen.height / scale)
    }

    @Test func phonesAreUnchanged() {
        for phone in phones {
            #expect(ReefScreen.scale(for: phone) == 1)
            #expect(ReefScreen.playfield(in: phone) == CGRect(origin: .zero, size: phone))
        }
    }

    /// As wide as the biggest phone and taller, so the maps and cards have room to spread out.
    @Test func anIPadDrawsTheBiggestPhonesWidthAndMore() {
        for iPad in iPads {
            let size = scene(on: iPad)
            #expect(abs(size.width - ReefScreen.largestPhone.width) < 0.001)
            #expect(size.height > ReefScreen.largestPhone.height)
        }
    }

    /// The same lanes and the same reach as on the biggest phone, centered, with the rest of the screen above and below.
    @Test func anIPadPlaysARoundInTheBiggestPhonesWater() {
        for iPad in iPads {
            let size = scene(on: iPad)
            let field = ReefScreen.playfield(in: size)
            #expect(field.height == ReefScreen.largestPhone.height)
            #expect(field.width == size.width)
            #expect(abs(field.minY - (size.height - field.maxY)) <= 1)
        }
    }

    /// The scene's view asks for 120 frames a second; on a ProMotion iPhone, iOS only allows more than 60 with the
    /// Info.plist key (MathReef-Info.plist), as Bigger Fish found when its credits stuttered.
    @MainActor @Test func theAppMayRunAt120FramesASecond() {
        #expect(ReefView.Container(frame: .zero).sceneView.preferredFramesPerSecond == 120)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone") as? Bool == true)
    }

    /// A touch on the screen lands in the scene's own points: the middle of an iPad is the middle of the scene.
    @MainActor @Test func touchesLandInTheScenesPoints() {
        let container = ReefView.Container(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        container.layoutIfNeeded()
        let size = scene(on: container.bounds.size)
        #expect(container.sceneView.bounds.size == size)
        for (screen, expected) in [
            (CGPoint(x: 590, y: 410), CGPoint(x: size.width / 2, y: size.height / 2)),
            (CGPoint(x: 0, y: 0), CGPoint.zero),
            (CGPoint(x: 1180, y: 820), CGPoint(x: size.width, y: size.height)),
        ] {
            let point = container.convert(screen, to: container.sceneView)
            #expect(abs(point.x - expected.x) < 0.01 && abs(point.y - expected.y) < 0.01)
        }
    }

    // MARK: Corners

    /// A closed iPhone Duo in landscape, in points, and its camera, in the top-left corner (as iOS 27.1 reports it).
    private let duoClosed = CGSize(width: 678, height: 466)
    private var duoCamera: CGRect { CGRect(x: 29, y: duoClosed.height - 66, width: 37, height: 37) }

    /// Nothing covers a corner of a phone or an iPad: their corners' controls stay where they've always been.
    @Test func cornersAreUnchangedWithNothingCovered() {
        for screen in phones + iPads + [duoClosed] {
            #expect(ReefCorners(size: screen, occlusions: []) == ReefCorners())
        }
    }

    /// A Dynamic Island sits at the middle of the edge in landscape, below the corners' controls.
    @Test func anIslandAtTheMiddleOfTheEdgeMovesNothing() {
        let phone = CGSize(width: 874, height: 402)
        for x in [0, phone.width - 37] {
            let island = CGRect(x: x, y: phone.height / 2 - 63, width: 37, height: 126)
            #expect(ReefCorners(size: phone, occlusions: [island]) == ReefCorners())
        }
    }

    /// The closed iPhone Duo's camera, in a top corner: that side's controls move clear of it, with room to spare, and the
    /// other side's stay put. Turned around, the camera is in a bottom corner, clear of them all.
    @Test func aCameraInATopCornerMovesThatSidesControlsClear() {
        let corners = ReefCorners(size: duoClosed, occlusions: [duoCamera])
        #expect(ReefCorners.phoneLeft + corners.left >= duoCamera.maxX + ReefCorners.gap)
        #expect(corners.right == 0)

        let topRight = duoCamera.offsetBy(dx: duoClosed.width - duoCamera.maxX - duoCamera.minX, dy: 0)
        let mirrored = ReefCorners(size: duoClosed, occlusions: [topRight])
        #expect(duoClosed.width - ReefCorners.phoneRight - mirrored.right <= topRight.minX - ReefCorners.gap)
        #expect(mirrored.left == 0)

        let turned = CGRect(x: duoClosed.width - duoCamera.maxX, y: duoCamera.minX, width: 37, height: 37)
        #expect(ReefCorners(size: duoClosed, occlusions: [turned]) == ReefCorners())
    }
}
