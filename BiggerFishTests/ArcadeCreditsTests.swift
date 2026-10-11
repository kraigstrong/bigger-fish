import Foundation
import ImageIO
import SpriteKit
import Testing
import UIKit
@testable import BiggerFish

/// The credits game (`CreditsScene`, from Settings): every name in `Credits.json`, eaten in a calm swim you can't lose,
/// that records nothing, lets you leave at any time, and reads every name to VoiceOver.
@MainActor
struct ArcadeCreditsTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private let names = ArcadeCredits.shipped.names.map(\.name)

    /// Sound, music, and vibration as given, in a test suite of their own rather than the player's.
    private func settings(on: Bool = true) -> ArcadeSettings {
        let settings = ArcadeSettings(defaults: UserDefaults(suiteName: "biggerFish.tests.credits")!)
        settings.soundEffectsOn = on
        settings.musicOn = on
        settings.vibrationOn = on
        return settings
    }

    private func present(_ scene: CreditsScene) -> SKView {
        let view = SKView(frame: CGRect(origin: .zero, size: GameTuning.playfieldSize))
        view.presentScene(scene)
        return view
    }

    // MARK: The names

    /// Design and the play-testers come first, exactly as Kraig gave them, then the music and sound effects, which are
    /// the ones Sounds/CREDITS.md names: a sound added or swapped there fails this until Credits.json follows.
    @Test func theNamesAreTheTestersThenWhatCreditsMDNames() throws {
        let credits = try #require(ArcadeCredits.load(), "Credits.json is missing from the app or doesn't decode")
        #expect(credits == ArcadeCredits.shipped)
        #expect(credits.groups.map(\.heading) == ["Design", "Play-testers", "Music", "Sound effects"])
        #expect(credits.groups[0].credits.map(\.name) == ["Megan S"])
        #expect(credits.groups[1].credits.map(\.name) == ["Chad H", "Adam A", "Andy W", "Riley S", "Reagan S"])
        #expect(credits.names.map(\.tag) == ["Design"] + Array(repeating: "Play-tester", count: 5)
            + ["Music · Tidal Groove", "Music · Aquarium Fish", "Sound effects"])

        let markdown = try String(contentsOf: Self.root.appendingPathComponent("BiggerFish/Sounds/CREDITS.md"), encoding: .utf8)
        func section(_ title: String) -> String {
            markdown.components(separatedBy: "\n## ").first { $0.hasPrefix(title) } ?? ""
        }
        // `  - Pixabay 560238, "Tidal Groove [Chill Pop Instrumental]" by tideblue (marked AI-generated)`
        let tracks = section("Music").matches(of: #/- (\w+) \d+, "([^"]+)" by ([^\s(]+)/#)
            .map { (source: String($0.1), title: String($0.2), creator: String($0.3)) }
        // `  - Mixkit 3192, "Egg bubble pop"`
        let libraries = Set(section("Sound effects").matches(of: #/- (\w+) \d+, "/#).map { String($0.1) })
        #expect(tracks.count == 2 && libraries == ["Mixkit"], "parsed \(tracks) and \(libraries)")

        func group(_ heading: String) -> [ArcadeCredits.Entry] { credits.groups.first { $0.heading == heading }?.credits ?? [] }
        let music = group("Music")
        #expect(music.map(\.name) == tracks.map(\.creator))
        for (entry, track) in zip(music, tracks) {
            #expect(track.title.hasPrefix(entry.work ?? "?"), "\(entry.name) made \(track.title)")
            #expect(entry.via == track.source)
        }
        #expect(group("Sound effects").map(\.name) == libraries.sorted())
    }

    // MARK: Playing it

    /// A player who goes for each name eats them all, in the file's order, and reaches the card in about a minute: each
    /// with the eat sound and a tap, growing a little (the camera easing out), then the clear chime.
    @Test func aPlayerEatsEveryNameInOrderInAboutAMinute() {
        let scene = CreditsScene(settings: settings())
        let view = present(scene)
        let run = scene.debugPlay()
        print("CREDITS finished=\(run.finished) seconds=\(String(format: "%.1f", run.seconds)) radius=\(scene.debugPlayer.targetRadius) zoom=\(scene.debugZoom)")
        #expect(run.finished && scene.debugCardShowing)
        #expect(scene.debugEatenNames == names)
        #expect(run.seconds > 45 && run.seconds < 100, "took \(run.seconds) s")
        let grown = scene.debugPlayer.targetRadius / GameTuning.baseRadius
        #expect(grown > 1.5 && grown < 2.5, "grew \(grown) times")
        #expect(scene.debugZoom < 0.9)
        #expect(scene.debugSounds == Array(repeating: .eat, count: names.count) + [.clear])
        #expect(scene.debugHaptics == Array(repeating: .meal, count: names.count) + [.finish])
        withExtendedLifetime(view) {}
    }

    /// One that goes by comes round again, next in line (before the name after it), so everyone is still eaten in order.
    @Test func aNameYouMissComesRoundAgain() {
        let scene = CreditsScene(settings: settings())
        let view = present(scene)
        let run = scene.debugPlay(.dodger(until: 12))
        #expect(run.finished)
        let releases = scene.debugReleases
        #expect(releases.count > names.count && releases.prefix(2) == [0, 0], "came in: \(releases)")
        #expect(scene.debugEatenNames == names)
        withExtendedLifetime(view) {}
    }

    /// Nothing eats you: sitting on the bottom or tapping at random, you swim on; and a name twice your size, right on you,
    /// is yours (in a level, it would eat you).
    @Test func nothingCanEatYou() {
        for style in [CreditsScene.DebugPlayer.passive, .flailing] {
            let scene = CreditsScene(settings: settings())
            let view = present(scene)
            var alwaysSwimming = true
            scene.debugPlay(style, limit: 80) {
                if case .beingSwallowed = scene.debugPlayer.state { alwaysSwimming = false }
                if scene.debugPlayer.state == .removed { alwaysSwimming = false }
            }
            #expect(alwaysSwimming && scene.debugPlayer.isAlive, "\(style)")
            withExtendedLifetime(view) {}
        }
        let scene = CreditsScene(settings: settings())
        let view = present(scene)
        scene.debugPutNameOnYou(scale: 2)
        scene.debugAdvance(seconds: 2.0 / 60)
        #expect(scene.debugPlayer.state != .swimming, "you should be swallowing it")
        scene.debugAdvance(seconds: 1.5)
        #expect(scene.debugPlayer.state == .swimming && scene.eaten == [0])
        withExtendedLifetime(view) {}
    }

    /// It's never given progress or analytics, and a whole play leaves every saved key as it was: progress, best times,
    /// the unlock, review requests, and the analytics queue. (The sound switches are left out: other tests flip them.)
    @Test func itRecordsNothing() {
        let switches: Set<String> = ["biggerFish.soundEffectsOn", "biggerFish.musicOn", "biggerFish.vibrationOn"]
        func saved() -> NSDictionary {
            NSDictionary(dictionary: UserDefaults.standard.dictionaryRepresentation()
                .filter { $0.key.hasPrefix("biggerFish.") && !switches.contains($0.key) })
        }
        let before = saved()
        let scene = CreditsScene(settings: settings())
        let view = present(scene)
        var exited = false
        scene.onExit = { exited = true }
        #expect(scene.debugPlay().finished)
        scene.debugTapDone()
        #expect(exited)
        #expect(saved() == before)
        withExtendedLifetime(view) {}
    }

    /// Skip leaves at any time, once; the card's button leaves too, after a moment (a finger still down from the last
    /// name doesn't). Either way the phone may sleep again.
    @Test func youCanLeaveAtAnyTime() {
        let scene = CreditsScene(settings: settings())
        let view = present(scene)
        var left = 0
        scene.onExit = { left += 1 }
        #expect(UIApplication.shared.isIdleTimerDisabled)
        scene.debugPlay(limit: 10)
        #expect(!scene.finished && scene.eaten.count < names.count)
        scene.leave()
        scene.leave()
        #expect(left == 1 && !UIApplication.shared.isIdleTimerDisabled)
        withExtendedLifetime(view) {}

        let done = CreditsScene(settings: settings())
        let doneView = present(done)
        var doneLeft = 0
        done.onExit = { doneLeft += 1 }
        #expect(done.debugPlay().finished)
        done.debugTapDone(after: 0.1)
        #expect(doneLeft == 0)
        done.debugTapDone()
        #expect(doneLeft == 1)
        withExtendedLifetime(doneView) {}
    }

    /// With every switch off in Settings: no sound and no haptics (and the music is the map's calm track, which the
    /// Music switch already governs).
    @Test func theSoundAndVibrationSwitchesAreRespected() {
        let scene = CreditsScene(settings: settings(on: false))
        let view = present(scene)
        #expect(scene.debugPlay().finished)
        #expect(scene.debugSounds.isEmpty && scene.debugHaptics.isEmpty)
        #expect(GameTuning.creditsMusic == .menu)
        withExtendedLifetime(view) {}
    }

    /// VoiceOver reads the whole list, every group and name, while you swim (Skip is beside it, in SwiftUI); at the end, the
    /// card and its button, which leaves as a tap does.
    @Test func voiceOverReadsEveryName() {
        let credits = ArcadeCredits.shipped
        for text in credits.groups.map(\.heading) + names { #expect(credits.spokenList.contains(text), "\(text)") }
        #expect(credits.spokenList.contains("Tidal Groove by tideblue from Pixabay"))
        let scene = CreditsScene(settings: settings())
        let view = present(scene)
        func elements() -> [UIAccessibilityElement] { (scene.accessibilityElements ?? []).compactMap { $0 as? UIAccessibilityElement } }
        #expect(elements().map(\.accessibilityLabel) == [credits.spokenList])
        #expect(scene.debugPlay().finished)
        let done = elements().compactMap { $0 as? ArcadeResultAccessibilityElement }.first
        #expect(elements().compactMap(\.accessibilityLabel).contains(credits.spokenList))
        #expect(done?.accessibilityLabel == CreditsScene.doneTitle && done?.accessibilityTraits.contains(.button) == true)
        var left = false
        scene.onExit = { left = true }
        #expect(done?.accessibilityActivate() == true && left)
        withExtendedLifetime(view) {}
    }

    /// Reduce Motion: thanks fade in place rather than float up, and names don't turn round.
    @Test func reduceMotionKeepsItStill() {
        func play(reduceMotion: Bool) -> (rise: CGFloat, turns: Int) {
            let scene = CreditsScene(reduceMotion: reduceMotion, settings: settings())
            let view = present(scene)
            defer { withExtendedLifetime(view) {} }
            // Each line seen, kept so a new one can't be mistaken for it.
            var lines: [(node: SKNode, start: CGFloat)] = [], rise: CGFloat = 0, turns = 0, headings: [Int: CGFloat] = [:]
            scene.debugPlay(limit: 40) {
                scene.debugRender()
                for s in scene.debugSwimmers {
                    if let was = headings[s.fish.id], was != s.fish.heading { turns += 1 }
                    headings[s.fish.id] = s.fish.heading
                }
                for line in scene.debugThanks {
                    guard let seen = lines.first(where: { $0.node === line }) else {
                        lines.append((line, line.position.y))
                        continue
                    }
                    rise = max(rise, line.position.y - seen.start)
                }
            }
            return (rise, turns)
        }
        let moving = play(reduceMotion: false), still = play(reduceMotion: true)
        #expect(moving.rise > 20 && moving.turns > 0, "\(moving)")
        #expect(still.rise == 0 && still.turns == 0, "\(still)")
    }

    /// Every tag reads upright at its own size whatever the zoom, sits over its fish under the top of the screen, and
    /// never overlaps another.
    @Test func tagsStayReadable() {
        let scene = CreditsScene(settings: settings())
        let view = present(scene)
        var problems: [String] = [], checked = 0
        scene.debugPlay {
            scene.debugRender()
            let shown = scene.debugSwimmers.filter { $0.fish.state == .swimming && !$0.tag.isHidden }
            for s in shown {
                checked += 1
                if s.tag.xScale != 1 || s.tag.yScale != 1 || s.tag.zRotation != 0 { problems.append("\(s.tag.credit.name) scaled or turned") }
                if s.tag.position.y + CreditTag.height > GameTuning.playfieldSize.height - GameTuning.creditsTagTopMargin + 1 {
                    problems.append("\(s.tag.credit.name) off the top at \(s.tag.position.y)")
                }
            }
            for (i, a) in shown.enumerated() {
                for b in shown.dropFirst(i + 1) where abs(a.tag.position.x - b.tag.position.x) < (a.tag.width + b.tag.width) / 2
                    && abs(a.tag.position.y - b.tag.position.y) < CreditTag.height {
                    problems.append("\(a.tag.credit.name) overlaps \(b.tag.credit.name)")
                }
            }
        }
        #expect(checked > 500)
        #expect(problems.isEmpty, "\(Set(problems).sorted().prefix(8))")
        withExtendedLifetime(view) {}
    }

    // MARK: Previews

    /// Writes frames of the credits to build/previews/credits-*.png when that folder exists (it's ignored by git), to
    /// look at: the opening line, swimming among names, a tag bursting, the thanks, late in the swim zoomed out, and the
    /// card.
    @Test func manualRenderPreviews() throws {
        let folder = Self.root.appendingPathComponent("build/previews")
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let scene = CreditsScene(reduceMotion: false, settings: settings(on: false))
        let view = present(scene)
        func save(_ name: String) throws {
            scene.debugRender()
            let texture = try #require(view.texture(from: scene))
            let url = folder.appendingPathComponent("credits-\(name).png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, texture.cgImage(), nil)
            #expect(CGImageDestinationFinalize(destination))
        }
        var frame = 0, eatenAt: [Int: Int] = [:], shots: Set<String> = []
        func shot(_ name: String, when: Bool) {
            guard when, !shots.contains(name) else { return }
            shots.insert(name)
            try? save(name)
        }
        scene.debugPlay {
            frame += 1
            let eaten = scene.eaten.count
            if eatenAt[eaten] == nil { eatenAt[eaten] = frame }
            scene.debugRender()
            let onScreen = scene.debugSwimmers.filter { $0.fish.state == .swimming && $0.tag.position.x > 380 && $0.tag.position.x < 700 }
            shot("intro", when: frame == 70)
            shot("swim", when: eaten == 1 && !onScreen.isEmpty)
            shot("pop", when: eaten == 2 && frame == eatenAt[2]! + 5)
            shot("thanks", when: eaten == 3 && frame == eatenAt[3]! + 24)
            shot("late", when: eaten == names.count - 1 && !onScreen.isEmpty)
        }
        scene.debugAdvance(seconds: 0.8)
        try save("card")
        withExtendedLifetime(view) {}
    }
}
