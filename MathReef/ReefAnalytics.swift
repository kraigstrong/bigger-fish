import Foundation

// First-party, anonymous counts: which levels get started and passed, how rounds end, and which
// crowns get earned. No identifiers of any kind, no timestamps, no device details, and nothing about
// which answers were chosen or how long anything took. Batches from different installs can't be told
// apart or linked. Milestones are reported once per install so the counts mean "how many players".
//
// While `isEnabled` is off, nothing is recorded or stored, let alone sent: play from before the
// privacy policy describes analytics must never leave the device later.

/// One analytics event. The initializers are private so an event can only be one of the two shapes
/// below; `ReefAnalyticsTests` pins the full set of keys a batch can contain.
struct AnalyticsEvent: Codable, Equatable {
    enum Kind: String, Codable { case milestone, round }
    enum Outcome: String, Codable { case finished, quit, abandoned }

    let kind: Kind
    /// Milestones only: "first_launch", "level_passed:add.make10", "crown:addition:gold", ...
    private(set) var name: String?
    /// Rounds only. `correct` is how far into the round (0...target), as the in-game progress label
    /// shows it; `stars` is set for finished rounds only.
    private(set) var level: String?
    private(set) var outcome: Outcome?
    private(set) var correct: Int?
    private(set) var target: Int?
    private(set) var stars: Int?

    private init(kind: Kind) { self.kind = kind }

    static func milestone(_ name: String) -> AnalyticsEvent {
        var event = AnalyticsEvent(kind: .milestone)
        event.name = name
        return event
    }

    static func round(level: String, outcome: Outcome, correct: Int, target: Int, stars: Int? = nil) -> AnalyticsEvent {
        var event = AnalyticsEvent(kind: .round)
        event.level = level
        event.outcome = outcome
        event.correct = correct
        event.target = target
        event.stars = outcome == .finished ? stars : nil
        return event
    }
}

/// What gets POSTed: the events plus which build sent them.
struct AnalyticsBatch: Codable, Equatable {
    let appVersion: String
    /// "appstore", "testflight", or "debug".
    let channel: String
    let events: [AnalyticsEvent]
}

protocol AnalyticsSender {
    func send(_ batch: AnalyticsBatch)
}

/// Records events at the right moments of play and queues them in UserDefaults until `flush()`.
final class ReefAnalytics {
    /// Off until the server exists and the privacy policy and `PrivacyInfo.xcprivacy` describe what's
    /// sent. While off, every method does nothing: no queue, no milestones marked, no pending round.
    static let isEnabled = false
    /// Placeholder until the server ships.
    static let endpoint = URL(string: "https://brightbench.app/api/math-reef/events")!
    /// Sent as `X-App-Key` to filter out stray bots. Not a secret: anyone can pull it out of the
    /// binary. The server's strict validation of every field is the real protection.
    static let appKey = "math-reef-placeholder-key"
    /// The oldest events are dropped past this.
    static let queueLimit = 200

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var channel: String {
        #if DEBUG
        return "debug"
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "testflight" : "appstore"
        #endif
    }

    /// The round being played, kept in memory and saved as pending while the app is inactive.
    private struct Round: Codable, Equatable {
        let level: String
        let target: Int
        var correct = 0
    }

    private let defaults: UserDefaults
    private let sender: AnalyticsSender
    private let enabled: Bool
    private var round: Round?

    private let queueKey = "mathReef.analytics.queue"
    private let reportedKey = "mathReef.analytics.reportedMilestones"
    private let pendingKey = "mathReef.analytics.pendingRound"

    init(
        defaults: UserDefaults = .standard,
        sender: AnalyticsSender = URLSessionAnalyticsSender(),
        enabled: Bool = ReefAnalytics.isEnabled
    ) {
        self.defaults = defaults
        self.sender = sender
        self.enabled = enabled
    }

    var queue: [AnalyticsEvent] {
        guard let data = defaults.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([AnalyticsEvent].self, from: data)) ?? []
    }

    // MARK: Moments of play

    /// Once per cold launch. A round still pending from last time was never finished or quit: the
    /// app was closed mid-round.
    func appLaunched() {
        guard enabled else { return }
        reportOnce("first_launch")
        if let data = defaults.data(forKey: pendingKey),
           let pending = try? JSONDecoder().decode(Round.self, from: data) {
            enqueue(.round(level: pending.level, outcome: .abandoned, correct: pending.correct, target: pending.target))
        }
        defaults.removeObject(forKey: pendingKey)
    }

    func roundStarted(level: Level, target: Int) {
        guard enabled else { return }
        round = Round(level: level.id, target: target)
        reportOnce("first_round")
        reportOnce("level_started:\(level.id)")
    }

    func roundProgress(correct: Int) {
        round?.correct = correct
    }

    /// `level_passed` is for the level played; levels a checkpoint passes along the way don't count.
    func roundFinished(_ summary: RoundSummary, level: Level, in world: World) {
        guard enabled else { return }
        let target = round?.target ?? summary.correct
        round = nil
        enqueue(.round(level: level.id, outcome: .finished, correct: summary.correct, target: target, stars: summary.stars))
        if summary.passed { reportOnce("level_passed:\(level.id)") }
        if let crown = summary.newCrown, crown != .none {
            reportOnce("crown:\(world.id):\(crown == .gold ? "gold" : "silver")")
        }
    }

    /// The close button during a round. Does nothing if no round is in progress (the instructions).
    func roundQuit() {
        guard let round else { return }
        self.round = nil
        enqueue(.round(level: round.level, outcome: .quit, correct: round.correct, target: round.target))
    }

    /// Saves a round in progress in case the app never comes back, then sends what's queued.
    func appResignedActive() {
        guard enabled else { return }
        if let round, let data = try? JSONEncoder().encode(round) {
            defaults.set(data, forKey: pendingKey)
        }
        flush()
    }

    /// Back from the background with the round still going, so it isn't abandoned.
    func appBecameActive() {
        if round != nil { defaults.removeObject(forKey: pendingKey) }
    }

    // MARK: Queue and sending

    /// Sends everything queued as one batch. Events leave the queue when sent, whether or not the
    /// request succeeds: a lost batch is dropped rather than retried forever.
    func flush() {
        guard enabled else { return }
        let events = queue
        guard !events.isEmpty else { return }
        defaults.removeObject(forKey: queueKey)
        sender.send(AnalyticsBatch(appVersion: Self.appVersion, channel: Self.channel, events: events))
    }

    /// Milestones are remembered as reported as soon as they're queued, so each is counted once per
    /// install even if its batch is later lost.
    private func reportOnce(_ milestone: String) {
        var reported = defaults.stringArray(forKey: reportedKey) ?? []
        guard !reported.contains(milestone) else { return }
        reported.append(milestone)
        defaults.set(reported, forKey: reportedKey)
        enqueue(.milestone(milestone))
    }

    private func enqueue(_ event: AnalyticsEvent) {
        let events = (queue + [event]).suffix(Self.queueLimit)
        if let data = try? JSONEncoder().encode(Array(events)) { defaults.set(data, forKey: queueKey) }
    }
}

/// POSTs a batch as JSON with no cookies, cache, or credentials, and ignores the response.
struct URLSessionAnalyticsSender: AnalyticsSender {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    func send(_ batch: AnalyticsBatch) {
        guard let body = try? JSONEncoder().encode(batch) else { return }
        var request = URLRequest(url: ReefAnalytics.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ReefAnalytics.appKey, forHTTPHeaderField: "X-App-Key")
        request.httpBody = body
        Self.session.dataTask(with: request).resume()
    }
}
