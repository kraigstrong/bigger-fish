import Foundation

/// The credits game's names (`Credits.json`), grouped under headings in the order they swim in: design, level design,
/// the play-testers, then the music, then the sound effects. Adding someone means adding them to the file, not code. The music and sound
/// credits mirror `Sounds/CREDITS.md`, and a test keeps the two in step.
struct ArcadeCredits: Decodable, Equatable {
    struct Group: Decodable, Equatable {
        /// What VoiceOver reads before the group's names: "Play-testers".
        let heading: String
        /// The small line on each of its names' tags: "Play-tester".
        let role: String
        let credits: [Entry]
    }

    struct Entry: Decodable, Equatable {
        /// Just as the person gave it ("Chad H"), or the creator's own handle ("tideblue").
        let name: String
        /// What they made, for the music: "Tidal Groove".
        var work: String? = nil
        /// Where it came from: "Pixabay".
        var via: String? = nil
    }

    /// One name as it swims: the name itself, and the line on its tag ("Play-tester", "Music · Tidal Groove").
    struct Credit: Equatable {
        let name: String
        let tag: String
    }

    let groups: [Group]

    /// Every name, in the order they swim in.
    var names: [Credit] {
        groups.flatMap { group in
            group.credits.map { Credit(name: $0.name, tag: ([group.role] + [$0.work].compactMap { $0 }).joined(separator: " · ")) }
        }
    }

    /// Everything VoiceOver reads: each heading, then its names. "Credits. Play-testers: Chad H, Adam A. Music: Tidal
    /// Groove by tideblue from Pixabay. Sound effects: Mixkit."
    var spokenList: String {
        let parts = groups.map { group in
            "\(group.heading): " + group.credits.map { entry in
                (entry.work.map { "\($0) by \(entry.name)" } ?? entry.name) + (entry.via.map { " from \($0)" } ?? "")
            }.joined(separator: ", ") + "."
        }
        return (["Credits."] + parts).joined(separator: " ")
    }

    /// The file in the app. A missing or unreadable file fails the tests; in the app it plays straight to the thanks.
    static let shipped = load() ?? ArcadeCredits(groups: [])

    static func load(from bundle: Bundle = .main) -> ArcadeCredits? {
        guard let url = bundle.url(forResource: "Credits", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ArcadeCredits.self, from: data)
    }
}
