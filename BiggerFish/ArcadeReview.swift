import Foundation

/// When Bigger Fish asks for an App Store review: after a high point (conquering a world, or a first Deep End clear),
/// the next time you're back on a map with nothing else on screen. Never on or right after the unlock screen, never
/// after a loss, at most `GameTuning.reviewRequestLimit` times, `GameTuning.reviewRetryInterval` apart, and never from
/// an Xcode or TestFlight build (TestFlight can't show the sheet). Kept on this device, apart from progress and
/// analytics. StoreKit doesn't say whether its sheet appeared, so this counts requests, not reviews. Modeled on Math
/// Reef's `ReefReview`.
final class ArcadeReview {
    private struct State: Codable {
        var pending = false
        var requestCount = 0
        var lastRequest: Date?
    }

    private let defaults: UserDefaults
    private static let key = "biggerFish.review.v1"
    private var state: State

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    /// A high point: the next quiet moment on a map may ask.
    func earned(now: Date = Date()) {
        guard isEligible(now: now) else { return }
        state.pending = true
        save()
    }

    /// The unlock screen showed: no asking until the next high point.
    func sawOffer() {
        guard state.pending else { return }
        state.pending = false
        save()
    }

    /// Whether to ask now. `channel` is the build's ("appstore", "testflight", or "debug"): only App Store builds ask.
    func shouldRequest(channel: String, now: Date = Date()) -> Bool {
        channel == "appstore" && state.pending && isEligible(now: now)
    }

    /// Call when handing the request to StoreKit.
    func didRequest(now: Date = Date()) {
        state.pending = false
        state.requestCount += 1
        state.lastRequest = now
        save()
    }

    private func isEligible(now: Date) -> Bool {
        guard state.requestCount < GameTuning.reviewRequestLimit else { return false }
        guard let last = state.lastRequest else { return true }
        return now.timeIntervalSince(last) >= GameTuning.reviewRetryInterval
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.key) }
    }
}
