import Foundation

// What the results screen says about a finished round, decided before anything is drawn so it can
// be tested without the scene.

struct RoundSummary: Equatable {
    let title: String
    let percent: Int
    let correct: Int
    let attempts: Int
    /// What the round did: unlocked a level, skipped ahead, finished the world, or what's still needed.
    let outcome: String
    let passed: Bool
    /// This round's stars, and how many of them beat the level's best (those pop in).
    let stars: Int
    let newStars: Int
    /// Set when this round earned the world a crown or upgraded silver to gold; it plays the crown
    /// presentation.
    let newCrown: Crown?
}

extension ProgressStore {
    /// Saves a finished round and describes it for the results screen.
    func recordRound(_ index: Int, in world: World, correct: Int, attempts: Int) -> RoundSummary {
        let hasNext = index + 1 < world.levels.count
        let alreadyUnlocked = hasNext && isUnlocked(index + 1, in: world)
        let wasSkipTest = isSkipTest(index, in: world)
        let starsBefore = record(for: world.levels[index]).stars
        let crownBefore = crown(for: world)

        let passed = finishRound(index, in: world, correct: correct, attempts: attempts)
        let stars = PassRule.stars(correct: correct, attempts: attempts)
        let crownAfter = crown(for: world)

        let outcome = if passed && wasSkipTest {
            "You skipped ahead!"
        } else if passed {
            !hasNext ? "\(world.title) complete!" : alreadyUnlocked ? "Next level is open." : "Level \(index + 2) unlocked!"
        } else {
            "Get 80% to unlock the next level."
        }
        return RoundSummary(
            title: passed ? "Level passed!" : stars > 0 ? "Nice try!" : "Keep practicing",
            percent: PassRule.percent(correct: correct, attempts: attempts),
            correct: correct,
            attempts: attempts,
            outcome: outcome,
            passed: passed,
            stars: stars,
            newStars: max(0, stars - starsBefore),
            newCrown: crownAfter != crownBefore && crownAfter != .none ? crownAfter : nil
        )
    }
}
