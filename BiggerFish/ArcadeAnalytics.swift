import Foundation

struct ArcadeMetricEvent: Codable, Equatable {
    enum Kind: String, Codable { case milestone, run, decision }
    let kind: Kind
    var name: String?
    var context: ArcadeMetricContext?
    var outcome: String?
    var cause: String?
    var replay: Bool?
    var attempt: Int?
    var summary: ArcadeRunMetrics?
}

struct ArcadeMetricBatch: Codable {
    let schema = 1
    let appVersion: String
    let build: String
    let channel: String
    let events: [ArcadeMetricEvent]

    enum CodingKeys: String, CodingKey { case schema, appVersion, build, channel, events }
}

protocol ArcadeMetricSender {
    func send(_ batch: ArcadeMetricBatch)
}

/// All calls originate on the UI thread. Local milestone markers and counters are never transmitted as IDs.
final class ArcadeAnalytics {
    // Beta collection: the endpoint and policy are live; App Store disclosures remain a release check.
    static let isEnabled = true
    static let revision = "2026-10-04.1"
    static let endpoint = URL(string: "https://brightbench.app/api/bigger-fish/events")!
    // Public noise filter, not authentication. Strict server validation is the protection.
    static let appKey = "bigger-fish-gameplay-v1"
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }
    static var defaultEnabled: Bool {
        #if DEBUG
        if ArcadePlaytest.selection != nil || ArcadePlaytest.planner != nil { return false }
        #endif
        return isEnabled && !isRunningTests
    }
    private let defaults: UserDefaults
    private let sender: ArcadeMetricSender
    let enabled: Bool
    private let prefix = "biggerFish.metrics.v1."
    private struct Queued: Codable {
        var event: ArcadeMetricEvent
        let appVersion: String
        let build: String
        let channel: String
    }
    private var pending: Queued?
    private var result: Queued?
    private var expectedWorldLevels: Int?

    init(defaults: UserDefaults = .standard, sender: ArcadeMetricSender = ArcadeURLMetricSender(), enabled: Bool = ArcadeAnalytics.defaultEnabled) {
        self.defaults = defaults; self.sender = sender; self.enabled = enabled
    }
    private var storedQueue: [Queued] {
        defaults.data(forKey: prefix + "queue").flatMap { try? JSONDecoder().decode([Queued].self, from: $0) } ?? []
    }
    var queue: [ArcadeMetricEvent] { storedQueue.map(\.event) }
    private func stamp(_ event: ArcadeMetricEvent) -> Queued {
        #if DEBUG
        let channel = "debug"
        #else
        let channel = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "testflight" : "appstore"
        #endif
        return Queued(event: event,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1", channel: channel)
    }
    func launched() {
        guard enabled else { return }
        milestone("first_launch", context: nil)
        if let data = defaults.data(forKey: prefix + "pending"), var old = try? JSONDecoder().decode(Queued.self, from: data) {
            old.event.outcome = "abandoned"; old.event.cause = "none"; old.event.summary?.fatalRatio = nil; enqueueStored(old)
        }
        defaults.removeObject(forKey: prefix + "pending")
        if let data = defaults.data(forKey: prefix + "result"), let old = try? JSONDecoder().decode(Queued.self, from: data) {
            enqueueStored(Queued(event: ArcadeMetricEvent(kind: .decision, name: "unknown", context: old.event.context, outcome: old.event.outcome), appVersion: old.appVersion, build: old.build, channel: old.channel))
        }
        defaults.removeObject(forKey: prefix + "result")
    }
    func start(_ context: ArcadeMetricContext, worldLevelCount: Int? = nil, alreadyCleared: Bool = false) {
        guard enabled else { return }
        expectedWorldLevels = worldLevelCount
        decide("retry", next: context)
        milestone("level_started", context: context)
        milestone("world_started", context: context)
        let key = contentKey(context)
        let replay = alreadyCleared || defaults.bool(forKey: prefix + "cleared." + key)
        let attempt = min(1000, defaults.integer(forKey: prefix + "attempt." + key) + 1)
        if !replay { defaults.set(attempt, forKey: prefix + "attempt." + key) }
        pending = stamp(ArcadeMetricEvent(kind: .run, context: context, outcome: "abandoned", cause: "none", replay: replay, attempt: replay ? 0 : attempt, summary: ArcadeRunMetrics()))
        checkpoint(ArcadeRunMetrics())
    }
    func checkpoint(_ summary: ArcadeRunMetrics) {
        guard enabled, pending != nil else { return }
        pending?.event.summary = summary
        defaults.set(try? JSONEncoder().encode(pending), forKey: prefix + "pending")
    }
    func finish(_ outcome: String, cause: String = "none", summary: ArcadeRunMetrics) {
        guard enabled, var event = pending else { return }
        event.event.outcome = outcome; event.event.cause = cause; event.event.summary = summary
        if outcome != "death" || cause != "predator" { event.event.summary?.fatalRatio = nil }
        pending = nil; defaults.removeObject(forKey: prefix + "pending")
        enqueueStored(event)
        if outcome == "win", let context = event.event.context {
            defaults.set(true, forKey: prefix + "cleared." + contentKey(context))
            milestone("level_cleared", context: context)
            var cleared = Set(defaults.stringArray(forKey: prefix + "world." + context.revision + "." + context.mode + "." + context.world) ?? [])
            cleared.insert(String(context.setup))
            defaults.set(Array(cleared), forKey: prefix + "world." + context.revision + "." + context.mode + "." + context.world)
            if let expectedWorldLevels, expectedWorldLevels > 0, cleared.count >= expectedWorldLevels {
                milestone("world_cleared", context: context, worldLevels: expectedWorldLevels)
            }
        }
        if outcome == "win" || outcome == "death" {
            result = event
            defaults.set(try? JSONEncoder().encode(event), forKey: prefix + "result")
        }
        // Sending is initiated off the gameplay/meal stack (URLSession does its own asynchronous work).
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }
    func leave() { decide("leave", next: nil) }
    private func decide(_ decision: String, next: ArcadeMetricContext?) {
        guard enabled, let old = result else { return }
        let same = old.event.context == next
        enqueueStored(Queued(event: ArcadeMetricEvent(kind: .decision, name: decision == "retry" && !same ? "next" : decision, context: old.event.context, outcome: old.event.outcome), appVersion: old.appVersion, build: old.build, channel: old.channel))
        result = nil; defaults.removeObject(forKey: prefix + "result")
    }
    private func contentKey(_ c: ArcadeMetricContext) -> String { "\(c.revision).\(c.mode).\(c.world).\(c.setup)" }
    /// Worlds had ten levels before completions were scoped by level count; they keep that unsuffixed key,
    /// so a world finished then doesn't report again.
    private static let originalWorldLevels = 10
    /// A world that gains levels (Shallow Reef's bonus levels) reports its completion again at its new size.
    private func milestone(_ name: String, context: ArcadeMetricContext?, worldLevels: Int? = nil) {
        var scope = name.hasPrefix("world_") ? "\(context!.revision).\(context!.mode).\(context!.world)" : context.map(contentKey) ?? "install"
        if let worldLevels, worldLevels != Self.originalWorldLevels { scope += ".\(worldLevels)" }
        let key = prefix + "milestone." + name + "." + scope
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        enqueue(ArcadeMetricEvent(kind: .milestone, name: name, context: context))
    }
    private func enqueue(_ event: ArcadeMetricEvent) { enqueueStored(stamp(event)) }
    private func enqueueStored(_ event: Queued) {
        defaults.set(try? JSONEncoder().encode(Array((storedQueue + [event]).suffix(100))), forKey: prefix + "queue")
    }
    /// At-most-once delivery: remove before sending, never retry uncertain deliveries without IDs.
    /// Offline events remain bounded until a flush; failed batches are dropped, like Math Reef.
    func flush() {
        guard enabled else { return }
        let events = storedQueue
        defaults.removeObject(forKey: prefix + "queue")
        let grouped = Dictionary(grouping: events) { "\($0.channel):\($0.appVersion):\($0.build)" }
        for group in grouped.values {
            guard let first = group.first else { continue }
            for offset in stride(from: 0, to: group.count, by: 25) {
                sender.send(ArcadeMetricBatch(appVersion: first.appVersion, build: first.build, channel: first.channel,
                    events: group[offset..<min(offset + 25, group.count)].map(\.event)))
            }
        }
    }
}

struct ArcadeURLMetricSender: ArcadeMetricSender {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()
    func send(_ batch: ArcadeMetricBatch) {
        guard let data = try? JSONEncoder().encode(batch) else { return }
        var request = URLRequest(url: ArcadeAnalytics.endpoint)
        request.httpMethod = "POST"; request.httpBody = data
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ArcadeAnalytics.appKey, forHTTPHeaderField: "X-App-Key")
        Self.session.dataTask(with: request).resume()
    }
}
