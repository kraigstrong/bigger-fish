import Foundation

/// When Bigger Fish asks for an App Store review: after a high point (a level beaten for the first time after
/// `GameTuning.reviewHardWonDeaths` deaths or more, or a first Deep End clear), the next time you're back on a map
/// after a win with nothing else on screen. Never on or right after the unlock screen, never after a loss, at most
/// `GameTuning.reviewRequestLimit` times, `GameTuning.reviewRetryInterval` apart, and never from an Xcode or TestFlight
/// build (TestFlight can't show the sheet). Kept on this device, apart from progress and analytics. StoreKit doesn't
/// say whether its sheet appeared, so this counts requests, not reviews. Modeled on Math Reef's `ReefReview`.
final class ArcadeReview {
    private struct State: Codable {
        var pending = false
        var requestCount = 0
        var lastRequest: Date?
        /// Deaths on each level not yet beaten, by level ID (`shallow-reef.8`), counted up to
        /// `GameTuning.reviewHardWonDeaths`. A state saved before deaths were counted loads with none.
        var deaths: [String: Int] = [:]

        init() {}

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            pending = try values.decode(Bool.self, forKey: .pending)
            requestCount = try values.decode(Int.self, forKey: .requestCount)
            lastRequest = try values.decodeIfPresent(Date.self, forKey: .lastRequest)
            deaths = try values.decodeIfPresent([String: Int].self, forKey: .deaths) ?? [:]
        }
    }

    private let defaults: UserDefaults
    private static let key = "biggerFish.review.v1"
    private var state: State

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    /// A death on a level not yet beaten (`level`: its ID, like `shallow-reef.8`), in any session.
    func died(on level: String) {
        guard state.requestCount < GameTuning.reviewRequestLimit else { return }
        state.deaths[level] = min((state.deaths[level] ?? 0) + 1, GameTuning.reviewHardWonDeaths)
        save()
    }

    /// A level beaten for the first time: a high point if it took `GameTuning.reviewHardWonDeaths` deaths or more, or
    /// it's in the Deep End. The next quiet moment on a map may ask.
    func firstCleared(_ level: String, deepEnd: Bool, now: Date = Date()) {
        let hardWon = (state.deaths.removeValue(forKey: level) ?? 0) >= GameTuning.reviewHardWonDeaths
        if (hardWon || deepEnd) && isEligible(now: now) { state.pending = true }
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
