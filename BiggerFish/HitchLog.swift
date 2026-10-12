#if DEBUG
import Foundation
import QuartzCore
import SpriteKit
import UIKit

// Xcode builds only: Release builds have none of this. Every slow frame anywhere in the app, which screen it was on,
// and what happened just before it, written beside the run recordings in Documents/ArcadeRuns, so
// `scripts/pull-arcade-runs.py` brings it back and `scripts/analyze-arcade-runs.py` reports it (its Hitches section).
//
// Two clocks time the frames. A SpriteKit scene (a level, the tutorial, the credits) times its own, from the top of
// each `update`, in every phase: that's the cadence the player sees. Everywhere else (the maps, Settings, the unlock,
// the conquered screen), a display link on the main run loop does. It pauses while a scene times its own, so it never
// asks the display for frames the scene didn't, which could change the very refresh rate being measured. A run-loop
// observer times how long the main thread worked without a break, so each hitch says whether the main thread was busy
// (its work) or the frame simply came late.

/// Something that happened, kept a moment in case the next frame is slow.
struct HitchEvent: Equatable {
    enum Kind: String {
        case screen, scene, phase, card, result, pause, resume, death, swallow, haptic, sound, music, save
        case hapticPrepare = "haptic_prepare", analyticsEvent = "analytics_event", analyticsSend = "analytics_send"
    }
    let kind: Kind
    /// Which one: the haptic and its generator, the sound, the card. Callers pass literals, so noting doesn't allocate.
    let detail: String
    /// When, in `CACurrentMediaTime` seconds.
    let at: CFTimeInterval
}

/// The latest `capacity` values; appending past it drops the oldest. Its storage is allocated once, up front, so
/// appending on the frame path doesn't allocate.
struct RingBuffer<Element> {
    let capacity: Int
    private var storage: [Element?]
    /// Where the next value goes.
    private var next = 0
    private(set) var count = 0

    init(capacity: Int) {
        precondition(capacity > 0, "A ring buffer holds at least one value")
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ element: Element) {
        storage[next] = element
        next = (next + 1) % capacity
        count = min(count + 1, capacity)
    }

    var newest: Element? { count == 0 ? nil : storage[(next - 1 + capacity) % capacity] }

    /// Every value held, newest first.
    var newestFirst: [Element] {
        (0..<count).map { storage[(next - 1 - $0 + capacity) % capacity]! }
    }

    mutating func removeAll() {
        for index in storage.indices { storage[index] = nil }
        next = 0
        count = 0
    }
}

/// Where the player was when a frame was slow.
struct HitchContext: Equatable {
    enum Screen: String {
        case launch, worldMap = "world_map", levelMap = "level_map", settings, unlock, conquered, tuning
        case level, tutorial, credits

        /// Shown as a sheet over a scene, which stays up underneath.
        var isSheet: Bool { self == .tuning }
    }
    var screen: Screen
    /// Which one: a level map's world (`kelp-forest`), a level (`kelp-forest.3`), the tutorial's beat.
    var detail: String
    /// A level's phase (ready, playing, paused, won, lost) or the credits' (start_card, swimming, end_card).
    var phase: String

    init(_ screen: Screen, detail: String = "", phase: String = "") {
        self.screen = screen
        self.detail = detail
        self.phase = phase
    }

    /// As each hitch records it.
    var fields: [String: Any] {
        var fields: [String: Any] = ["screen": screen.rawValue]
        if !detail.isEmpty { fields["detail"] = detail }
        if !phase.isEmpty { fields["phase"] = phase }
        return fields
    }
}

/// The app's slow frames, each with its screen and phase, its timing, and the events just before it (see the top of
/// this file). Main thread only.
final class HitchLog {
    /// The app's, when run recordings are on: Xcode builds, not under tests or with -arcadeDisableRunRecording.
    static let shared: HitchLog? = makeDefault()

    /// A frame is slow at 1.5 display intervals or more. Frames come in whole refreshes, so this sits halfway between
    /// a frame on time and one that missed a refresh: timing jitter never trips it, and every missed refresh does
    /// (12.5 ms at 120 Hz, 25 ms at 60). A single missed refresh at 120 Hz is barely visible, but a run of them is
    /// the judder a phone shows and the simulator doesn't, and the report sorts the worst first.
    static let slowFrameIntervals = 1.5
    static let eventCapacity = 16
    /// How many of the latest events each hitch keeps, and from how long before it.
    static let eventsPerHitch = 8
    static let eventWindow: CFTimeInterval = 2
    /// At most this many hitches are written a second; the rest are counted in the next one's `suppressed`, so a long
    /// stretch of slow frames can't flood the files.
    static let hitchesPerSecond = 20
    /// Sessions with hitches outside a level that keep their `hitches-…jsonl`.
    static let retainedSessions = 30

    private let now: () -> CFTimeInterval
    private let write: ([String: Any]) -> Void
    private(set) var events = RingBuffer<HitchEvent>(capacity: HitchLog.eventCapacity)
    /// The SwiftUI screen showing (`ContentView`).
    private(set) var screen = HitchContext(.launch)
    /// The scene timing its own frames, while one is up, and where it says it is.
    private weak var sceneOwner: AnyObject?
    private var sceneContext = HitchContext(.level)
    /// The level's run recording while one is open: a hitch then goes into it, on the run's clock.
    var runRecording: (([String: Any]) -> Void)?

    private var preferredFramesPerSecond = 60
    private var screenMaximumFramesPerSecond = 60
    /// The frame interval the scene up asks for.
    private(set) var sceneInterval: CFTimeInterval = 1.0 / 60
    private var lastSceneFrame: TimeInterval?
    private var updateStarted: CFTimeInterval?
    private var lastUpdateWork: CFTimeInterval?
    private var lastDisplayFrame: TimeInterval?
    /// The last frame from either source. A scene's first frame, and the display link's first after a scene goes, time
    /// from it: the handoff (building and presenting a scene, or leaving one) is often the slowest frame of all.
    private var lastAnyFrame: TimeInterval?
    /// A sheet over the scene (Tuning): the scene underneath stops speaking for the screen, and the display link times
    /// frames until the sheet goes.
    private var overlayUp = false
    /// When the main thread last woke to work, if it's working now, and its longest stretch since the last frame.
    private var busySince: CFTimeInterval?
    private var longestBusy: CFTimeInterval = 0
    private var windowStart = -CFTimeInterval.infinity
    private var windowCount = 0
    private var suppressed = 0
    /// In the background, or under Notification Center: frames then aren't the game's.
    private var active = true
    private var watchdog: HitchWatchdog?

    /// `write`: where a hitch goes when no level's run is recording.
    init(now: @escaping () -> CFTimeInterval = CACurrentMediaTime, write: @escaping ([String: Any]) -> Void) {
        self.now = now
        self.write = write
    }

    /// Where a slow frame happened: the scene's own account while one is up, otherwise the SwiftUI screen (a sheet over
    /// the scene included).
    var context: HitchContext { sceneOwner == nil || overlayUp ? screen : sceneContext }
    /// Whether the scene, rather than the display link, is timing frames.
    private var sceneTiming: Bool { sceneOwner != nil && !overlayUp }

    // MARK: What happened

    func note(_ kind: HitchEvent.Kind, _ detail: String = "") {
        guard Thread.isMainThread else { return }
        events.append(HitchEvent(kind: kind, detail: detail, at: now()))
    }

    /// The SwiftUI screen showing; a scene, while it's up, says more about itself.
    func show(_ screen: HitchContext) {
        guard screen != self.screen else { return }
        self.screen = screen
        note(.screen, screen.screen.rawValue)
        // A sheet over the scene speaks for the screen while it's up.
        let overlay = sceneOwner != nil && screen.screen.isSheet
        guard overlay != overlayUp else { return }
        overlayUp = overlay
        if overlay { lastDisplayFrame = lastAnyFrame } else { lastSceneFrame = lastAnyFrame }
        updateStarted = nil
        lastUpdateWork = nil
        watchdog?.isPaused = sceneTiming
    }

    // MARK: Scenes

    /// A scene is up and times its own frames, at the rate its view asks for.
    func enterScene(_ owner: AnyObject, _ context: HitchContext, view: SKView?) {
        let screenMaximum = view?.window?.windowScene?.screen.maximumFramesPerSecond ?? Self.connectedScreenMaximum
        enterScene(owner, context, framesPerSecond: view?.preferredFramesPerSecond ?? 60, screenMaximum: screenMaximum)
    }

    func enterScene(_ owner: AnyObject, _ context: HitchContext, framesPerSecond: Int, screenMaximum: Int) {
        sceneOwner = owner
        sceneContext = context
        preferredFramesPerSecond = framesPerSecond
        screenMaximumFramesPerSecond = screenMaximum
        updateSceneInterval()
        // Its first frame times from the last one shown, so building and presenting it is measured.
        lastSceneFrame = lastAnyFrame
        updateStarted = nil
        lastUpdateWork = nil
        overlayUp = sceneOwner != nil && screen.screen.isSheet
        watchdog?.isPaused = sceneTiming
        note(.scene, context.screen.rawValue)
    }

    /// The scene's level, beat, or phase changed.
    func updateScene(_ owner: AnyObject, _ context: HitchContext) {
        guard owner === sceneOwner else { return }
        sceneContext = context
    }

    /// The scene is gone: the display link takes over (unless another scene has come up meanwhile).
    func leaveScene(_ owner: AnyObject) {
        guard owner === sceneOwner else { return }
        sceneOwner = nil
        overlayUp = false
        // The display link's first frame times from the scene's last, so leaving it is measured.
        lastDisplayFrame = lastAnyFrame
        watchdog?.isPaused = false
    }

    /// At the top of the scene's `update`, with its timestamp: times the frame since the last one.
    func frameBegan(_ owner: AnyObject, timestamp: TimeInterval) {
        guard owner === sceneOwner, !overlayUp else { return }
        let time = now()
        let work = takeWork(at: time)
        defer {
            lastSceneFrame = timestamp
            lastAnyFrame = timestamp
            updateStarted = time
        }
        guard let previous = lastSceneFrame else { return }
        check(elapsed: timestamp - previous, interval: sceneInterval, work: work, update: lastUpdateWork, source: "scene",
              at: time)
    }

    /// At the end of the scene's `update`: its own work, for the next frame's account.
    func frameEnded(_ owner: AnyObject) {
        guard owner === sceneOwner, !overlayUp, let updateStarted else { return }
        lastUpdateWork = now() - updateStarted
    }

    // MARK: Everywhere else

    /// A display link frame, while no scene is up.
    func displayFrame(timestamp: TimeInterval, interval: CFTimeInterval) {
        let time = now()
        let work = takeWork(at: time)
        guard !sceneTiming else { return }
        defer {
            lastDisplayFrame = timestamp
            lastAnyFrame = timestamp
        }
        guard let previous = lastDisplayFrame else { return }
        check(elapsed: timestamp - previous, interval: interval, work: work, update: nil, source: "display", at: time)
    }

    /// The main thread woke to work, and is about to sleep: its run loop's observers.
    func mainThreadWoke() { busySince = now() }
    func mainThreadSleeps() {
        if let busySince { longestBusy = max(longestBusy, now() - busySince) }
        busySince = nil
    }

    func resignActive() { active = false }
    func becomeActive() {
        active = true
        // Time away isn't a slow frame.
        lastSceneFrame = nil
        lastDisplayFrame = nil
        lastAnyFrame = nil
        busySince = nil
        longestBusy = 0
    }

    /// The frame interval a view asking for `preferred` frames a second gets: at most the screen's, and 60 in Low Power
    /// Mode.
    static func frameInterval(preferred: Int, screenMaximum: Int, lowPower: Bool) -> CFTimeInterval {
        var rate = screenMaximum > 0 ? screenMaximum : 60
        if preferred > 0 { rate = min(rate, preferred) }
        if lowPower { rate = min(rate, 60) }
        return 1 / CFTimeInterval(rate)
    }

    // MARK: Recording

    /// The longest the main thread worked without a break since the last frame, the stretch it's in included.
    private func takeWork(at time: CFTimeInterval) -> CFTimeInterval {
        let work = max(longestBusy, busySince.map { time - $0 } ?? 0)
        longestBusy = 0
        return work
    }

    private func check(elapsed: CFTimeInterval, interval: CFTimeInterval, work: CFTimeInterval, update: CFTimeInterval?,
                       source: String, at time: CFTimeInterval) {
        guard active, interval > 0, elapsed >= interval * Self.slowFrameIntervals else { return }
        if time - windowStart >= 1 {
            windowStart = time
            windowCount = 0
        }
        guard windowCount < Self.hitchesPerSecond else {
            suppressed += 1
            return
        }
        windowCount += 1
        var record = context.fields
        record["source"] = source
        record["elapsedMs"] = Self.milliseconds(elapsed)
        record["intervalMs"] = Self.milliseconds(interval)
        record["missedFrames"] = max(1, Int((elapsed / interval).rounded()) - 1)
        record["workMs"] = Self.milliseconds(work)
        if let update { record["updateMs"] = Self.milliseconds(update) }
        record["events"] = recentEvents(at: time)
        if suppressed > 0 {
            record["suppressed"] = suppressed
            suppressed = 0
        }
        if let runRecording { runRecording(record) } else { write(record) }
    }

    /// The latest events, newest first, each with how long before the hitch it happened.
    private func recentEvents(at time: CFTimeInterval) -> [[String: Any]] {
        events.newestFirst.prefix(Self.eventsPerHitch).filter { time - $0.at <= Self.eventWindow }.map { event in
            var fields: [String: Any] = ["event": event.kind.rawValue, "agoMs": Self.milliseconds(time - event.at)]
            if !event.detail.isEmpty { fields["detail"] = event.detail }
            return fields
        }
    }

    /// To a tenth of a millisecond, as a decimal so the file reads 34.3 rather than 34.299999999999997.
    private static func milliseconds(_ seconds: CFTimeInterval) -> NSDecimalNumber {
        NSDecimalNumber(decimal: Decimal(Int((seconds * 10_000).rounded())) / 10)
    }

    private func updateSceneInterval() {
        sceneInterval = Self.frameInterval(preferred: preferredFramesPerSecond, screenMaximum: screenMaximumFramesPerSecond,
                                           lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    private static var connectedScreenMaximum: Int {
        UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }.first ?? 60
    }

    private static func makeDefault() -> HitchLog? {
        guard let directory = ArcadeRunRecorder.defaultDirectory else { return nil }
        let started = CACurrentMediaTime()
        var file: ArcadeRunRecorder?
        let log = HitchLog { fields in
            // A file of its own, from the first hitch outside a level.
            if file == nil {
                let created = ArcadeRunRecorder(directory: directory, prefix: "hitches", retained: HitchLog.retainedSessions)
                let info = Bundle.main.infoDictionary
                created.event("hitch_session", time: 0, fields: [
                    "appVersion": info?["CFBundleShortVersionString"] as? String ?? "unknown",
                    "build": info?["CFBundleVersion"] as? String ?? "unknown",
                    "screenMaximumFramesPerSecond": HitchLog.connectedScreenMaximum,
                    "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
                    "slowFrameIntervals": HitchLog.slowFrameIntervals,
                ])
                file = created
            }
            file?.event("hitch", time: CACurrentMediaTime() - started, fields: fields)
        }
        log.startWatching()
        return log
    }

    private func startWatching() {
        let watchdog = HitchWatchdog { [weak self] timestamp, interval in
            self?.displayFrame(timestamp: timestamp, interval: interval)
        }
        watchdog.isPaused = sceneOwner != nil
        self.watchdog = watchdog
        // First to see the main thread wake, and last before it sleeps: after Core Animation's commit, which is part of
        // a frame's work.
        let woke = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) {
            [weak self] _, _ in self?.mainThreadWoke()
        }
        let sleeps = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) {
            [weak self] _, _ in self?.mainThreadSleeps()
        }
        for observer in [woke, sleeps].compactMap({ $0 }) { CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes) }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resignActive()
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.becomeActive()
        }
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateSceneInterval()
        }
    }
}

/// The display link that times frames outside the scenes, on the main run loop in every mode (scrolling included).
private final class HitchWatchdog: NSObject {
    private let tick: (TimeInterval, CFTimeInterval) -> Void
    private var link: CADisplayLink?

    init(tick: @escaping (TimeInterval, CFTimeInterval) -> Void) {
        self.tick = tick
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    var isPaused: Bool {
        get { link?.isPaused ?? true }
        set { link?.isPaused = newValue }
    }

    @objc private func step(_ link: CADisplayLink) {
        tick(link.timestamp, link.targetTimestamp - link.timestamp)
    }
}
#endif
