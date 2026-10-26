import Foundation

struct ArcadeMetricEvent: Codable, Equatable {
    /// `offer`, `purchase`, and `restore` are the paywall funnel's (sent only with `sendsPaywallEvents` on); `endless`,
    /// `shop`, `earned`, and `outfit` the Open Water's and the pearl shop's (only with `sendsOpenWaterEvents` on).
    enum Kind: String, Codable { case milestone, run, decision, offer, purchase, restore, endless, shop, earned, outfit }
    let kind: Kind
    var name: String?
    var context: ArcadeMetricContext?
    var outcome: String?
    var cause: String?
    var replay: Bool?
    var attempt: Int?
    var summary: ArcadeRunMetrics?
    // The paywall funnel's fields. Left nil, they're left out of the JSON, so other events encode as they always have.
    /// Where the unlock's screen was opened from (`ArcadeAnalytics.OfferSource`), or "settings" for a restore there.
    var source: String?
    /// On an offer: the first this install has been shown, from anywhere.
    var first: Bool?
    /// On a run, while the unlock is on sale: whether this player had it.
    var unlocked: Bool?
    // The Open Water's and the pearl shop's fields, left out of the JSON like the paywall's when nil.
    /// On a campaign run: whether your fish wore any look.
    var dressed: Bool?
    /// On an `endless` event: the run.
    var openWater: ArcadeOpenWaterMetrics?
    /// On a `shop` visit: pearls in hand as it opened, the looks bought, and on the install's first purchase, the Open
    /// Water runs finished before it.
    var wallet: Int?
    var bought: [String]?
    var firstPurchaseRuns: Int?
    /// On an `earned` event: the look.
    var id: String?
    /// On an `outfit` event: what your fish wore, a look per kind.
    var pieces: [String]?
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
    /// The Open Water's own content revision, sent with every run in place of a level's: bump it when the run's worlds
    /// or their order (`GameTuning.openWaterWorlds`), its ramp (`openWaterFirstLevel`, the speed-up), the way its levels
    /// are dealt (`OpenWater.spec`), or the planner change, so the report keeps runs on different rules apart.
    static let openWaterRevision = "2026-10-26.2"
    /// Events wait on the device and go in batches: when this many are waiting, when the app goes to the background
    /// (or a level is interrupted), and at launch. Each send is a write to the stats server's Redis, billed per command,
    /// and the same counters in one batch are added up into one.
    static let batchSize = 25
    static let endpoint = URL(string: "https://brightbench.app/api/bigger-fish/events")!
    // Public noise filter, not authentication. Strict server validation is the protection.
    static let appKey = "bigger-fish-gameplay-v1"
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }
    /// Simulator builds never collect: Xcode's and agents' runs there aren't play worth counting (or paying for).
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    static var defaultEnabled: Bool {
        #if DEBUG
        if ArcadePlaytest.selection != nil || ArcadePlaytest.planner != nil || ArcadePlaytest.screen != nil
            || StoreCapture.moment != nil { return false }
        #endif
        return isEnabled && !isRunningTests && !isSimulator
    }
    private let defaults: UserDefaults
    private let sender: ArcadeMetricSender
    let enabled: Bool
    /// `sendsPaywallEvents`, or a test's choice.
    private let sendsPaywall: Bool
    /// `sendsOpenWaterEvents`, or a test's choice.
    private let sendsOpenWater: Bool
    private let prefix = "biggerFish.metrics.v1."
    private struct Queued: Codable {
        var event: ArcadeMetricEvent
        let appVersion: String
        let build: String
        let channel: String
    }
    private var pending: Queued?
    private var pendingOpenWater: Queued?
    private var result: Queued?
    /// Whether this launch's first run has been played (its outfit is reported then, if any).
    private var playedThisLaunch = false
    private var expectedWorldLevels: Int?

    init(defaults: UserDefaults = .standard, sender: ArcadeMetricSender = ArcadeURLMetricSender(), enabled: Bool = ArcadeAnalytics.defaultEnabled,
         paywallEvents: Bool = ArcadeAnalytics.sendsPaywallEvents, openWaterEvents: Bool = ArcadeAnalytics.sendsOpenWaterEvents) {
        self.defaults = defaults; self.sender = sender; self.enabled = enabled; self.sendsPaywall = paywallEvents
        self.sendsOpenWater = openWaterEvents
    }
    private var storedQueue: [Queued] {
        defaults.data(forKey: prefix + "queue").flatMap { try? JSONDecoder().decode([Queued].self, from: $0) } ?? []
    }
    var queue: [ArcadeMetricEvent] { storedQueue.map(\.event) }
    /// Where this build came from: "debug" (Xcode), "testflight", or "appstore".
    static var channel: String {
        #if DEBUG
        "debug"
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "testflight" : "appstore"
        #endif
    }
    private func stamp(_ event: ArcadeMetricEvent) -> Queued {
        let channel = Self.channel
        return Queued(event: event,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1", channel: channel)
    }
    /// The first-launch tutorial: started, finished, or skipped (once each per install). Off until the stats server
    /// accepts these milestones (it rejects a whole batch with a name it doesn't know) and the Bigger Fish privacy
    /// page discloses them; then turn on `sendsTutorialMilestones`.
    enum TutorialMilestone: String { case started = "tutorial_started", completed = "tutorial_completed", skipped = "tutorial_skipped" }
    static let sendsTutorialMilestones = false
    func tutorial(_ event: TutorialMilestone) {
        guard enabled, Self.sendsTutorialMilestones else { return }
        milestone(event.rawValue, context: nil)
    }

    /// The paywall funnel (#123): where the unlock's screen was shown from, how buying or restoring it went, each
    /// world's "conquered" milestone (its tenth level beaten for the first time), and whether a run was played with the
    /// unlock. brightbench.app accepts these and the Bigger Fish privacy page describes them (BrightBench#62). It goes on
    /// in the same release as `ArcadeUnlock.isSelling` (#156): before, there's nothing to count, and after, an offer
    /// shown before it's on isn't remembered, so a later one would be reported as the install's first. Turned off, none
    /// of them is sent or saved, and every other event encodes exactly as it did before.
    static let sendsPaywallEvents = true

    /// Where the unlock's screen was opened from.
    enum OfferSource: String, CaseIterable {
        /// A padlocked level, tapped on its world's level map.
        case padlockedLevel = "padlocked_level"
        /// Next level, on a win's card, onto a padlocked level.
        case nextLevel = "next_level"
        /// The Unlock all button on the world map.
        case unlockAll = "unlock_all"
        /// A world with no free levels, tapped on the world map. None today: every world has some.
        case lockedWorld = "locked_world"
        /// A world conquered without the unlock: its conquered screen is the offer. Shallow Reef, in practice, though a
        /// world beaten for free before the unlock went on sale shows it once too.
        case conquered
        /// The day's free Open Water runs used up: Open Water on the world map, or Unlock on a run's card.
        case openWaterLimit = "open_water_limit"
    }

    /// Whether the player has the unlock, while it's on sale; nil when it isn't, since then everything is open to
    /// everyone. Each run carries it, so results can be split by it.
    var hasUnlock: Bool?

    /// The unlock's screen was shown. Counted every time it shows; `first` marks the first this install has seen.
    func offerShown(_ source: OfferSource) {
        guard enabled, sendsPaywall else { return }
        let key = prefix + "offerShown"
        let first = !defaults.bool(forKey: key)
        defaults.set(true, forKey: key)
        enqueue(ArcadeMetricEvent(kind: .offer, source: source.rawValue, first: first))
    }

    /// How a tap on the unlock's buy button ended, and on which screen.
    func purchase(_ outcome: ArcadePurchases.PurchaseOutcome, from source: OfferSource) {
        guard enabled, sendsPaywall else { return }
        enqueue(ArcadeMetricEvent(kind: .purchase, outcome: outcome.rawValue, source: source.rawValue))
    }

    /// How Restore purchase ended on the unlock's screen, and what opened it.
    func restore(found: Bool, from source: OfferSource) { restore(found: found, place: source.rawValue) }
    /// How Restore purchase ended in Settings.
    func restoreInSettings(found: Bool) { restore(found: found, place: "settings") }
    /// Not reaching the App Store counts as "not_found", as it does on screen.
    private func restore(found: Bool, place: String) {
        guard enabled, sendsPaywall else { return }
        enqueue(ArcadeMetricEvent(kind: .restore, outcome: found ? "restored" : "not_found", source: place))
    }

    /// The app went to the background: everything waiting goes now, rather than wait for a full batch or the next launch
    /// (a player who leaves for good would never send it).
    func backgrounded() {
        guard enabled else { return }
        flush()
    }

    func launched() {
        guard enabled else { return }
        milestone("first_launch", context: nil)
        if let data = defaults.data(forKey: prefix + "pending"), var old = try? JSONDecoder().decode(Queued.self, from: data) {
            old.event.outcome = "abandoned"; old.event.cause = "none"; old.event.summary?.fatalRatio = nil; enqueueStored(old)
        }
        defaults.removeObject(forKey: prefix + "pending")
        if let data = defaults.data(forKey: prefix + "pendingOpenWater"), var old = try? JSONDecoder().decode(Queued.self, from: data) {
            old.event.outcome = "abandoned"; old.event.cause = "none"; enqueueStored(old)
        }
        defaults.removeObject(forKey: prefix + "pendingOpenWater")
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
        pending = stamp(ArcadeMetricEvent(kind: .run, context: context, outcome: "abandoned", cause: "none", replay: replay, attempt: replay ? 0 : attempt, summary: ArcadeRunMetrics(),
            unlocked: sendsPaywall ? hasUnlock : nil, dressed: sendsOpenWater ? !wearing.isEmpty : nil))
        checkpoint(ArcadeRunMetrics())
        reportOutfit()
    }
    func checkpoint(_ summary: ArcadeRunMetrics) {
        guard enabled, pending != nil else { return }
        #if DEBUG
        HitchLog.shared?.note(.analyticsEvent, "checkpoint saved")
        #endif
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
            // Conquered: the world's tenth level beaten for the first time. Its levels open in order, so that's every
            // main level beaten, the moment its conquered screen shows. (`world_cleared` waits for the Deep End too.)
            if sendsPaywall, context.mode == "campaign", context.level == ArcadeWorld.mainLevelCount, event.event.replay == false {
                milestone("world_conquered", context: context)
            }
        }
        if outcome == "win" || outcome == "death" {
            result = event
            defaults.set(try? JSONEncoder().encode(event), forKey: prefix + "result")
        }
    }
    func leave() { decide("leave", next: nil) }

    // MARK: The Open Water and the pearl shop

    /// The Open Water and the pearl shop: a summary of each run, where it ended, and what happened after; each visit to the
    /// shop and what it bought; looks earned; and what your fish wears. On since brightbench.app accepts these events
    /// (kraigstrong/BrightBench#85; it rejects a whole batch over one it doesn't know) and the Bigger Fish privacy page
    /// describes them. Turned off, none of them is sent or saved, and every other event encodes exactly as before.
    static let sendsOpenWaterEvents = true

    /// Every Open Water run has the same context, never its own seed: each run's seed would make a new row on the stats
    /// server, and it caps those a day.
    static let openWaterContext = ArcadeMetricContext(world: "open-water", level: 1, setup: 1, seed: "0", mode: "endless",
                                                      revision: ArcadeAnalytics.openWaterRevision)

    /// Whether the Open Water and the shop are reported (the scene starts a run's numbers only then).
    var collectsOpenWater: Bool { enabled && sendsOpenWater }

    /// The looks your fish wears now (IDs, a kind each), kept up to date by the app: runs say whether it wore any, and a
    /// launch's first run reports which.
    var wearing: [String] = []

    /// An Open Water run began, from its first level. Like a campaign start, it settles what the last lost run led to.
    func startOpenWater() {
        guard collectsOpenWater else { return }
        let context = Self.openWaterContext
        decide("retry", next: context)
        installMilestone("open_water_started", context: context)
        pendingOpenWater = stamp(ArcadeMetricEvent(kind: .endless, context: context, outcome: "abandoned", cause: "none",
            unlocked: sendsPaywall ? hasUnlock : nil, openWater: ArcadeOpenWaterMetrics(dressed: !wearing.isEmpty)))
        checkpointOpenWater(ArcadeOpenWaterMetrics(dressed: !wearing.isEmpty))
        reportOutfit()
    }

    /// The run so far, saved: if the app is closed in the middle, it's reported as left unfinished at the next launch.
    func checkpointOpenWater(_ run: ArcadeOpenWaterMetrics) {
        guard collectsOpenWater, pendingOpenWater != nil else { return }
        pendingOpenWater?.event.openWater = run
        defaults.set(try? JSONEncoder().encode(pendingOpenWater), forKey: prefix + "pendingOpenWater")
    }

    /// The run went all the way round the worlds for the first time on this install.
    func openWaterWentRound() {
        guard collectsOpenWater else { return }
        installMilestone("open_water_round", context: Self.openWaterContext)
    }

    /// The run ended: `death` (with its cause) or `quit`. A death's Retry or leaving is reported as its decision.
    func finishOpenWater(_ outcome: String, cause: String = "none", run: ArcadeOpenWaterMetrics) {
        guard collectsOpenWater, var event = pendingOpenWater else { return }
        event.event.outcome = outcome; event.event.cause = outcome == "death" ? cause : "none"; event.event.openWater = run
        pendingOpenWater = nil; defaults.removeObject(forKey: prefix + "pendingOpenWater")
        enqueueStored(event)
        defaults.set(min(10000, defaults.integer(forKey: prefix + "openWaterRuns") + 1), forKey: prefix + "openWaterRuns")
        if outcome == "death" {
            result = event
            defaults.set(try? JSONEncoder().encode(event), forKey: prefix + "result")
        }
    }

    /// Where the pearl shop was opened from.
    enum ShopSource: String, CaseIterable {
        /// The world map's pearl button.
        case map
        /// The Shop button on an Open Water run's card.
        case runCard = "run_card"
    }

    /// One visit to the pearl shop, as it goes: where from, the pearls in hand as it opened, whether this player had
    /// bought a look before, and the looks bought.
    struct ShopVisit: Equatable {
        let source: ShopSource
        let wallet: Int
        let hadBought: Bool
        private(set) var bought: [String] = []

        init(source: ShopSource, wallet: Int, hadBought: Bool) {
            self.source = source; self.wallet = wallet; self.hadBought = hadBought
        }

        /// A look bought on this visit.
        mutating func add(_ id: String) {
            if !bought.contains(id) { bought.append(id) }
        }
    }

    /// A visit to the shop ended (it closed, or the app went to the background with it open). Sent with the next batch.
    func shopVisited(_ visit: ShopVisit) {
        guard collectsOpenWater else { return }
        var event = ArcadeMetricEvent(kind: .shop, source: visit.source.rawValue)
        event.wallet = min(100_000, max(0, visit.wallet))
        event.bought = Array(visit.bought.prefix(64))
        let key = prefix + "purchased"
        if !visit.bought.isEmpty && !defaults.bool(forKey: key) {
            defaults.set(true, forKey: key)
            if !visit.hadBought { event.firstPurchaseRuns = defaults.integer(forKey: prefix + "openWaterRuns") }
        }
        enqueue(event)
    }

    /// The looks earned so far (`ArcadeProgress.earnedLooks`): each is reported once per install.
    func earned(_ ids: [String]) {
        guard collectsOpenWater else { return }
        for id in ids where !defaults.bool(forKey: prefix + "earned." + id) {
            defaults.set(true, forKey: prefix + "earned." + id)
            var event = ArcadeMetricEvent(kind: .earned)
            event.id = id
            enqueue(event)
        }
    }

    /// At a launch's first run, if your fish wears any looks, which: counted piece by piece, never with a run or level.
    private func reportOutfit() {
        guard sendsOpenWater, !playedThisLaunch else { return }
        playedThisLaunch = true
        guard !wearing.isEmpty else { return }
        var event = ArcadeMetricEvent(kind: .outfit)
        event.pieces = wearing.sorted()
        enqueue(event)
    }

    /// A milestone sent once per install, whatever the Open Water's revision.
    private func installMilestone(_ name: String, context: ArcadeMetricContext) {
        let key = prefix + "milestone." + name + ".install"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        enqueue(ArcadeMetricEvent(kind: .milestone, name: name, context: context))
    }
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
        #if DEBUG
        HitchLog.shared?.note(.analyticsEvent, "queued")
        #endif
        let queue = Array((storedQueue + [event]).suffix(100))
        defaults.set(try? JSONEncoder().encode(queue), forKey: prefix + "queue")
        // A full batch goes, initiated off the gameplay/meal stack (URLSession does its own asynchronous work).
        if queue.count >= Self.batchSize { DispatchQueue.main.async { [weak self] in self?.flush() } }
    }
    /// At-most-once delivery: remove before sending, never retry uncertain deliveries without IDs.
    /// Offline events remain bounded until a flush; failed batches are dropped, like Math Reef.
    func flush() {
        guard enabled else { return }
        let events = storedQueue
        #if DEBUG
        if !events.isEmpty { HitchLog.shared?.note(.analyticsSend, "flush") }
        #endif
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
    /// Encoding a batch and starting its request happen here, off the main thread: the first send of a session sets up
    /// the network, which held up a frame (a level's first death, its first send, stuttered).
    private static let queue = DispatchQueue(label: "biggerFish.metrics.send", qos: .utility)
    /// Sets up the session ahead of the first send, off the main thread (at launch).
    static func warmUp() { queue.async { _ = session } }
    func send(_ batch: ArcadeMetricBatch) {
        Self.queue.async {
            guard let data = try? JSONEncoder().encode(batch) else { return }
            var request = URLRequest(url: ArcadeAnalytics.endpoint)
            request.httpMethod = "POST"; request.httpBody = data
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(ArcadeAnalytics.appKey, forHTTPHeaderField: "X-App-Key")
            Self.session.dataTask(with: request).resume()
        }
    }
}
