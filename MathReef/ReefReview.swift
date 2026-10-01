import Foundation

/// Review timing stays on this device, separate from progress and anonymous analytics.
/// Queue after a crown; request only in the gated grown-up area. StoreKit doesn't tell us
/// whether its sheet appeared or a review was submitted, so we count requests, not reviews.
final class ReefReview {
    private struct State: Codable {
        var pending = false
        var requestCount = 0
        var lastRequest: Date?
    }

    private let defaults: UserDefaults
    private let key = "mathReef.review.v1"
    private var state: State

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    /// Existing crowns qualify too, including progress earned during the beta.
    func finishedRound(passed: Bool, hasCrown: Bool, now: Date = Date()) {
        guard passed, hasCrown, isEligible(now: now) else { return }
        state.pending = true
        save()
    }

    func shouldRequest(now: Date = Date()) -> Bool {
        state.pending && isEligible(now: now)
    }

    /// Call only when handing a request to StoreKit in an active window.
    func didRequest(now: Date = Date()) {
        guard shouldRequest(now: now) else { return }
        state.pending = false
        state.requestCount += 1
        state.lastRequest = now
        save()
    }

    private func isEligible(now: Date) -> Bool {
        guard state.requestCount < 2 else { return false }
        guard let last = state.lastRequest else { return true }
        return now.timeIntervalSince(last) >= ReefTuning.reviewRetryInterval
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key) }
    }
}
