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
}
