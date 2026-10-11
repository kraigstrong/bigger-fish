import CoreGraphics
import FishKit
import SpriteKit
import Testing
@testable import BiggerFish

struct ArcadeEncounterTests {
    @MainActor private func played(_ world: ArcadeWorld, _ index: Int, _ check: (GameScene) -> Void) {
        let scene = GameScene(world: world, levelIndex: index)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        view.presentScene(scene)
        scene.debugStart()
        check(scene)
        withExtendedLifetime(view) {}
    }

    @MainActor @Test func unmetPlannedFishPartOnScreenAndEatEachOtherOnceYouPass() {
        for world: ArcadeWorld in [.shallowReef, .jellyBloom] {
            for index in [0, 1, 9] {
                played(world, index) { #expect($0.debugProtectedFishYieldCheck(), "\(world.title) \(index + 1)") }
            }
        }
    }

    @MainActor @Test func movementAvoidanceAllowsARealAIBellBounce() {
        played(.jellyBloom, 1) { #expect($0.debugAIMovementAllowsBellLanding()) }
    }

    @MainActor @Test func aiFishCanBounceWithoutDyingFromStingers() {
        for index in [0, 1] {
            played(.jellyBloom, index) { scene in
                #expect(scene.debugAIFallOntoDome())
                #expect(scene.debugTouchTentacles(playerVictim: false))
                #expect(scene.debugTouchTentacles(playerVictim: true))
            }
        }
    }

    @Test func separationAnticipatesApproachesAndIgnoresDistantSwimmers() {
        let approaching = EncounterSteering.separation(relative: CGVector(dx: -80, dy: 0),
            velocity: CGVector(dx: 100, dy: 0), reach: 50, stableDirection: -1)
        #expect((approaching?.dx ?? 0) < 0)
        #expect(EncounterSteering.separation(relative: CGVector(dx: -80, dy: 0),
            velocity: CGVector(dx: -100, dy: 0), reach: 50, stableDirection: -1) == nil)
        #expect(EncounterSteering.separation(relative: CGVector(dx: -300, dy: 0),
            velocity: CGVector(dx: 100, dy: 0), reach: 50, stableDirection: -1) == nil)
        let overlap = EncounterSteering.separation(relative: .zero, velocity: .zero,
            reach: 50, stableDirection: 1)
        #expect((overlap?.dx ?? 0) > 0)
    }

    @Test func protectionExpiresAtTheLocalDistanceBoundary() {
        let first = EncounterLease(home: .zero, releaseDistance: 100)
        let later = EncounterLease(home: .zero, releaseDistance: 300)
        #expect(first.isProtected(distance: 99.999))
        #expect(!first.isProtected(distance: 100))
        #expect(later.isProtected(distance: 100))
    }

    @MainActor @Test func scenePreservesFoodBeforeReleaseAndAllowsAICompetitionAfterIt() {
        for world: ArcadeWorld in [.shallowReef, .jellyBloom] {
            for index in [0, 4, 9] {
                played(world, index) { #expect($0.debugEncounterProtectionLifecycle(), "\(world.title) \(index + 1)") }
            }
        }
    }
}
