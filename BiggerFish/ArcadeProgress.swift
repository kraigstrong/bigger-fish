import Combine
import Foundation

/// A player's progress. It must always load: every field falls back to its default when a save doesn't have
/// it (a save from before the field existed), and fields a save has that this version doesn't know (a save from a
/// later version, perhaps another device's in iCloud) are kept exactly as they were, so saving never drops them.
/// Never rename these keys or the level IDs stored in them, and never change a field's type: an older version reads a
/// field it can't decode as missing, so add a new key instead.
///
/// Progress is backed up to the player's iCloud and merged (`merged(withCloud:)`) so that syncing only ever adds: a
/// level cleared on any device stays cleared. A new field needs a key in `CodingKeys` and a merge rule.
struct ArcadeSave: Codable, Equatable {
    var clearedLevels: Set<String> = []
    var bestTimes: [String: Double] = [:]
    var hasSeenJellyLesson = false
    /// Worlds whose "conquered" unlock screen has been shown.
    var seenUnlocks: Set<String>? = nil
    /// The first-launch tutorial has been shown (finished, skipped, or left).
    var hasSeenTutorial: Bool? = nil
    /// The Open Water's pearls: taken and spent, each counted by the install that took or spent them
    /// (`ArcadeProgress.install`), so two devices' pearls add up and spending on one can't be undone by the other.
    var pearlsEarned: [String: Int]? = nil
    var pearlsSpent: [String: Int]? = nil
    /// The pearl shop's items bought (`PearlItem` IDs), and what's worn.
    var ownedLooks: Set<String>? = nil
    var wornLook: WornLook? = nil
    /// The Open Water's best run: the most fish eaten in one.
    var openWaterBest: Int? = nil
    /// The furthest level any Open Water run has reached (counting from 0), for the looks it earns.
    var openWaterFurthest: Int? = nil
    /// The shop's looks seen there, so those added since are marked new. Before any, the first shop's
    /// (`GameTuning.pearlShopFirstLooks`).
    var seenLooks: Set<String>? = nil
    /// Looks saved to wear again in a tap, by slot ("1", "2", "3"): what each wears and when it was saved, so the
    /// latest save of a slot on any device is kept.
    var savedOutfits: [String: WornLook]? = nil
    /// The looks earned (`PearlItem.earnedBy`), kept from the moment each was, so one stays the player's whatever
    /// becomes of its goal: made harder, sold instead, retired, or a crown's when a world joins the campaign.
    var earnedLooks: Set<String>? = nil
    /// Fields this version doesn't know, from a later version, kept as they were.
    var laterFields: [String: SaveValue] = [:]

    /// Every field the save stores. Encoding and merging switch over these, so a new one doesn't compile until it's
    /// saved and has a merge rule.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case clearedLevels, bestTimes, hasSeenJellyLesson, seenUnlocks, hasSeenTutorial
        case pearlsEarned, pearlsSpent, ownedLooks, wornLook
        case openWaterBest, openWaterFurthest, seenLooks, savedOutfits, earnedLooks
    }

    /// What's worn (`PlayerLook`): an item ID for each kind worn, and when it was last changed (seconds since 1970),
    /// so the latest change on any device is what you wear everywhere.
    struct WornLook: Codable, Equatable {
        var items: [String: String]
        var changed: Double

        /// The later change; at the same moment, either way round the same one.
        static func latest(_ a: WornLook, _ b: WornLook) -> WornLook {
            if a.changed != b.changed { return a.changed > b.changed ? a : b }
            let order = { (look: WornLook) in
                look.items.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            }
            return order(a) >= order(b) ? a : b
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clearedLevels = (try? values.decodeIfPresent(Set<String>.self, forKey: .clearedLevels)) ?? []
        bestTimes = (try? values.decodeIfPresent([String: Double].self, forKey: .bestTimes)) ?? [:]
        hasSeenJellyLesson = (try? values.decodeIfPresent(Bool.self, forKey: .hasSeenJellyLesson)) ?? false
        seenUnlocks = try? values.decodeIfPresent(Set<String>.self, forKey: .seenUnlocks)
        hasSeenTutorial = try? values.decodeIfPresent(Bool.self, forKey: .hasSeenTutorial)
        pearlsEarned = try? values.decodeIfPresent([String: Int].self, forKey: .pearlsEarned)
        pearlsSpent = try? values.decodeIfPresent([String: Int].self, forKey: .pearlsSpent)
        ownedLooks = try? values.decodeIfPresent(Set<String>.self, forKey: .ownedLooks)
        wornLook = try? values.decodeIfPresent(WornLook.self, forKey: .wornLook)
        openWaterBest = try? values.decodeIfPresent(Int.self, forKey: .openWaterBest)
        openWaterFurthest = try? values.decodeIfPresent(Int.self, forKey: .openWaterFurthest)
        seenLooks = try? values.decodeIfPresent(Set<String>.self, forKey: .seenLooks)
        savedOutfits = try? values.decodeIfPresent([String: WornLook].self, forKey: .savedOutfits)
        earnedLooks = try? values.decodeIfPresent(Set<String>.self, forKey: .earnedLooks)
        let all = try decoder.container(keyedBy: SaveKey.self)
        for key in all.allKeys where CodingKeys(stringValue: key.stringValue) == nil {
            laterFields[key.stringValue] = try? all.decode(SaveValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SaveKey.self)
        for (key, value) in laterFields where CodingKeys(stringValue: key) == nil {
            try container.encode(value, forKey: SaveKey(key))
        }
        for key in CodingKeys.allCases {
            let field = SaveKey(key.stringValue)
            switch key {
            case .clearedLevels: try container.encode(clearedLevels, forKey: field)
            case .bestTimes: try container.encode(bestTimes, forKey: field)
            case .hasSeenJellyLesson: try container.encode(hasSeenJellyLesson, forKey: field)
            case .seenUnlocks: try container.encodeIfPresent(seenUnlocks, forKey: field)
            case .hasSeenTutorial: try container.encodeIfPresent(hasSeenTutorial, forKey: field)
            case .pearlsEarned: try container.encodeIfPresent(pearlsEarned, forKey: field)
            case .pearlsSpent: try container.encodeIfPresent(pearlsSpent, forKey: field)
            case .ownedLooks: try container.encodeIfPresent(ownedLooks, forKey: field)
            case .wornLook: try container.encodeIfPresent(wornLook, forKey: field)
            case .openWaterBest: try container.encodeIfPresent(openWaterBest, forKey: field)
            case .openWaterFurthest: try container.encodeIfPresent(openWaterFurthest, forKey: field)
            case .seenLooks: try container.encodeIfPresent(seenLooks, forKey: field)
            case .savedOutfits: try container.encodeIfPresent(savedOutfits, forKey: field)
            case .earnedLooks: try container.encodeIfPresent(earnedLooks, forKey: field)
            }
        }
    }

    /// This save with iCloud's merged in. Merging only ever adds, so syncing can never un-clear a level: cleared levels
    /// and seen "conquered" screens are united, each level keeps the faster best time, and a lesson or tutorial seen on
    /// either side stays seen. Each install's pearls taken and spent keep the larger count, things bought are united,
    /// the look changed last is worn, the Open Water's better best run and further level are kept, looks seen in the shop
    /// are united, each outfit slot keeps its latest save, and looks earned are united. It comes out the same whichever
    /// save is which, except for fields from a later version: this version never changes those, so iCloud's (the latest
    /// any device wrote) is kept when both sides have one.
    func merged(withCloud cloud: ArcadeSave) -> ArcadeSave {
        var merged = self
        for key in CodingKeys.allCases {
            switch key {
            case .clearedLevels: merged.clearedLevels.formUnion(cloud.clearedLevels)
            case .bestTimes: merged.bestTimes.merge(cloud.bestTimes) { Swift.min($0, $1) }
            case .hasSeenJellyLesson: merged.hasSeenJellyLesson = hasSeenJellyLesson || cloud.hasSeenJellyLesson
            case .seenUnlocks:
                if let theirs = cloud.seenUnlocks { merged.seenUnlocks = (seenUnlocks ?? []).union(theirs) }
            case .hasSeenTutorial:
                if let theirs = cloud.hasSeenTutorial { merged.hasSeenTutorial = hasSeenTutorial == true || theirs }
            case .pearlsEarned:
                if let theirs = cloud.pearlsEarned { merged.pearlsEarned = (pearlsEarned ?? [:]).merging(theirs, uniquingKeysWith: Swift.max) }
            case .pearlsSpent:
                if let theirs = cloud.pearlsSpent { merged.pearlsSpent = (pearlsSpent ?? [:]).merging(theirs, uniquingKeysWith: Swift.max) }
            case .ownedLooks:
                if let theirs = cloud.ownedLooks { merged.ownedLooks = (ownedLooks ?? []).union(theirs) }
            case .wornLook:
                if let theirs = cloud.wornLook { merged.wornLook = wornLook.map { WornLook.latest($0, theirs) } ?? theirs }
            case .openWaterBest:
                if let theirs = cloud.openWaterBest { merged.openWaterBest = Swift.max(openWaterBest ?? 0, theirs) }
            case .openWaterFurthest:
                if let theirs = cloud.openWaterFurthest { merged.openWaterFurthest = Swift.max(openWaterFurthest ?? 0, theirs) }
            case .seenLooks:
                if let theirs = cloud.seenLooks { merged.seenLooks = (seenLooks ?? []).union(theirs) }
            case .savedOutfits:
                if let theirs = cloud.savedOutfits {
                    merged.savedOutfits = (savedOutfits ?? [:]).merging(theirs) { WornLook.latest($0, $1) }
                }
            case .earnedLooks:
                if let theirs = cloud.earnedLooks { merged.earnedLooks = (earnedLooks ?? []).union(theirs) }
            }
        }
        merged.laterFields.merge(cloud.laterFields) { _, theirs in theirs }
        return merged
    }
}

/// Any JSON value: how a field from a later version is kept, exactly as it was.
enum SaveValue: Codable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([SaveValue])
    case object([String: SaveValue])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let bool = try? value.decode(Bool.self) {
            self = .bool(bool)
        } else if let integer = try? value.decode(Int.self) {
            self = .integer(integer)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let array = try? value.decode([SaveValue].self) {
            self = .array(array)
        } else {
            self = .object(try value.decode([String: SaveValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let bool): try value.encode(bool)
        case .integer(let integer): try value.encode(integer)
        case .number(let number): try value.encode(number)
        case .string(let string): try value.encode(string)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        }
    }
}

/// Any key in a save, known or not.
private struct SaveKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ key: String) { stringValue = key }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Where progress is backed up: the player's own iCloud (`NSUbiquitousKeyValueStore`), or a test's stand-in. When its
/// values change from outside the app (another device's progress, the first download after an install, or a change of
/// Apple ID), it posts `NSUbiquitousKeyValueStore.didChangeExternallyNotification` with itself as the object.
protocol ArcadeCloudStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: ArcadeCloudStore {}

final class ArcadeProgress: ObservableObject {
    @Published private(set) var save: ArcadeSave
    private let defaults: UserDefaults
    /// The player's iCloud, where progress is backed up and merged from; nil keeps it on the device alone.
    private let cloud: ArcadeCloudStore?
    private var cloudChanges: NSObjectProtocol?
    static let key = "biggerFish.campaign.v1"

    /// Where a save that couldn't be read at all is kept, so the next save can't destroy it.
    static let unreadableKey = key + ".unreadable"
    /// Where an iCloud save that couldn't be read is kept on the device: it's never trusted over this device's
    /// progress, and the next backup replaces it.
    static let unreadableCloudKey = key + ".unreadableCloud"

    /// The progress saved in `defaults`. The player's real save, in standard defaults, is backed up to iCloud; a save of
    /// its own (a Debug playtest's, a store capture's staged one, a test's) never is.
    convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, cloud: Self.backup(for: defaults, iCloud: Self.iCloud))
    }

    /// With `cloud` nil, progress stays on the device alone, as it did before iCloud backup.
    init(defaults: UserDefaults, cloud: ArcadeCloudStore?) {
        self.defaults = defaults
        self.cloud = cloud
        if let data = defaults.data(forKey: Self.key) {
            if let loaded = try? JSONDecoder().decode(ArcadeSave.self, from: data) {
                save = loaded
            } else {
                // Not even a JSON object (any object loads, field by field): keep the original, and start afresh.
                defaults.set(data, forKey: Self.unreadableKey)
                save = ArcadeSave()
            }
        } else {
            save = ArcadeSave()
        }
        // A save from before looks earned were kept has them kept now.
        if keepEarnedLooks() { writeLocal() }
        guard let cloud else { return }
        // Every change merges, whatever its reason: another device's progress, the first download after an install,
        // or a change of Apple ID. None of them ever removes progress from this device.
        cloudChanges = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            self?.syncWithCloud()
        }
        cloud.synchronize()
        syncWithCloud()
    }

    deinit {
        if let cloudChanges { NotificationCenter.default.removeObserver(cloudChanges) }
    }

    /// The player's own iCloud key-value storage, except in test runs, which never touch it. Signed out of iCloud, or
    /// with iCloud turned off for the game, it keeps values on the device only, so the game plays as it always has.
    static var iCloud: ArcadeCloudStore? {
        ArcadeAnalytics.isRunningTests ? nil : NSUbiquitousKeyValueStore.default
    }

    /// Only the player's real save, in standard defaults, is backed up to `iCloud`. A save of its own never is: a Debug
    /// playtest's (`ArcadePlaytest.suiteName`) or a store capture's or footage's staged progress (`StoreCapture.suiteName`,
    /// `StoreFootage.suiteName`).
    static func backup(for defaults: UserDefaults, iCloud: @autoclosure () -> ArcadeCloudStore?) -> ArcadeCloudStore? {
        defaults === UserDefaults.standard ? iCloud() : nil
    }

    func isCleared(_ world: ArcadeWorld, _ index: Int) -> Bool {
        save.clearedLevels.contains(world.levelID(index))
    }

    func isOpen(_ world: ArcadeWorld, _ index: Int) -> Bool {
        guard (0..<world.levelCount).contains(index) else { return false }
        #if DEBUG
        // A world still being prototyped (on the map, not yet in the campaign) has every level open for playtesting.
        if !ArcadeWorld.campaign.contains(world) { return true }
        #endif
        return index == 0 || isCleared(world, index) || isCleared(world, index - 1)
    }

    /// How many of the world's main levels, and of its Deep End, are cleared.
    func clearedCounts(in world: ArcadeWorld) -> (main: Int, deepEnd: Int) {
        let cleared = (0..<world.levelCount).filter { isCleared(world, $0) }
        let deep = cleared.filter(ArcadeWorld.isDeepEnd).count
        return (cleared.count - deep, deep)
    }

    func nextLevel(in world: ArcadeWorld) -> Int {
        (0..<world.levelCount).first { !isCleared(world, $0) } ?? 0
    }

    /// Completed campaigns stay focused on the final stop when returning to their map.
    /// The level map's marker: the level you just left when coming back from one, otherwise the first
    /// level not yet cleared (or the last level once the world is complete).
    func mapFocus(in world: ArcadeWorld, returningFrom left: Int? = nil) -> Int {
        if let left, (0..<world.levelCount).contains(left) { return left }
        return (0..<world.levelCount).first { !isCleared(world, $0) } ?? max(0, world.levelCount - 1)
    }

    func clear(_ world: ArcadeWorld, _ index: Int, seconds: Double) {
        guard (0..<world.levelCount).contains(index), seconds.isFinite, seconds >= 0 else { return }
        let id = world.levelID(index)
        save.clearedLevels.insert(id)
        save.bestTimes[id] = min(save.bestTimes[id] ?? seconds, seconds)
        persist()
    }

    /// Debug A/B testing: a new player starts the world from level 1. It's the one way progress is ever removed, so it
    /// replaces iCloud's copy rather than merging with it, which would bring the levels straight back. (Another device
    /// that still has them brings them back when it next syncs.)
    func reset(_ world: ArcadeWorld) {
        // Everything else iCloud has stays: only this world starts over.
        if let cloud, let theirs = readSave(in: cloud) { save = save.merged(withCloud: theirs) }
        let prefix = world.rawValue + "."
        save.clearedLevels = save.clearedLevels.filter { !$0.hasPrefix(prefix) }
        save.bestTimes = save.bestTimes.filter { !$0.key.hasPrefix(prefix) }
        writeLocal()
        if let cloud { write(save, to: cloud) }
    }

    /// A world whose tenth level is beaten but whose "conquered" screen (opening its Deep End) the player hasn't had,
    /// shown at launch: players who beat it before that screen existed. With several, the furthest along first.
    var unseenUnlock: ArcadeWorld? {
        ArcadeWorld.campaign.last { world in
            isCleared(world, ArcadeWorld.mainLevelCount - 1) && !(save.seenUnlocks ?? []).contains(world.rawValue)
        }
    }

    /// Marks this world's "conquered" screen as shown. Each world's opens its own Deep End, and worlds can be played
    /// in any order, so it says nothing about other worlds'.
    func sawUnlock(_ world: ArcadeWorld) {
        save.seenUnlocks = (save.seenUnlocks ?? []).union([world.rawValue])
        persist()
    }

    /// Only a new player sees the tutorial: someone updating with levels already cleared knows the game.
    var needsTutorial: Bool { save.hasSeenTutorial != true && save.clearedLevels.isEmpty }

    func sawTutorial() {
        save.hasSeenTutorial = true
        persist()
    }

    func sawJellyLesson() {
        save.hasSeenJellyLesson = true
        persist()
    }

    // MARK: Pearls

    /// This install's name in the pearl counts (`ArcadeSave.pearlsEarned`): made once and kept on the device, it goes
    /// nowhere but the player's own iCloud, with their progress.
    private lazy var install: String = {
        let key = Self.key + ".install"
        if let id = defaults.string(forKey: key) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }()

    /// Pearls to spend: every install's taken, less every install's spent.
    var pearls: Int {
        max(0, (save.pearlsEarned ?? [:]).values.reduce(0, +) - (save.pearlsSpent ?? [:]).values.reduce(0, +))
    }

    /// Pearls taken in the Open Water (or, in Xcode builds, the shop's gift).
    func earnPearls(_ count: Int) {
        guard count > 0 else { return }
        save.pearlsEarned = (save.pearlsEarned ?? [:]).merging([install: count], uniquingKeysWith: +)
        persist()
    }

    /// The Open Water's best run, in fish eaten: 0 before any.
    var openWaterBest: Int { save.openWaterBest ?? 0 }

    /// The furthest level an Open Water run has reached (counting from 0).
    var openWaterFurthest: Int { save.openWaterFurthest ?? 0 }

    /// An Open Water run's end, with its fish eaten and the furthest level it reached: kept if either is the best yet.
    /// The looks it earned that weren't had before.
    @discardableResult func recordOpenWaterRun(fish: Int, furthest: Int = 0) -> [PearlItem] {
        guard fish > openWaterBest || furthest > openWaterFurthest else { return [] }
        let before = Set(earnedLooks.map(\.id))
        if fish > openWaterBest { save.openWaterBest = fish }
        if furthest > openWaterFurthest { save.openWaterFurthest = furthest }
        persist()
        return earnedLooks.filter { !before.contains($0.id) }
    }

    /// Whether what `goal` asks has been done: an Open Water run's best, or a crown on the map. Owning what it earns
    /// goes by `earnedLooks` instead: a look, once earned, is kept.
    func hasDone(_ goal: PearlGoal) -> Bool {
        func conquered(_ world: ArcadeWorld, deepEnd: Bool) -> Bool {
            let main = ArcadeWorld.mainLevelCount
            let levels = deepEnd ? main..<world.levelCount : 0..<min(main, world.levelCount)
            return !levels.isEmpty && levels.allSatisfy { isCleared(world, $0) }
        }
        switch goal {
        case .fishInOneRun(let fish): return openWaterBest >= fish
        case .openWaterLevel(let level): return openWaterFurthest >= level
        case .conquerAWorld: return ArcadeWorld.campaign.contains { conquered($0, deepEnd: false) }
        case .conquerADeepEnd: return ArcadeWorld.campaign.contains { conquered($0, deepEnd: true) }
        case .conquerEveryDeepEnd: return ArcadeWorld.campaign.allSatisfy { conquered($0, deepEnd: true) }
        }
    }

    /// The looks earned, not bought: kept from when they were earned, or with their goal done now (and not retired).
    var earnedLooks: [PearlItem] {
        GameTuning.pearlShop.filter { $0.earnedBy != nil && (save.earnedLooks?.contains($0.id) == true || earnsNow($0)) }
    }

    /// A look still to be earned whose goal is done: retired, it's no longer earned.
    private func earnsNow(_ item: PearlItem) -> Bool { !item.retired && item.earnedBy.map(hasDone) == true }

    /// Keeps each look whose goal is done as earned, so nothing that later becomes of the goal takes it back. Whether
    /// any is new.
    @discardableResult private func keepEarnedLooks() -> Bool {
        let kept = save.earnedLooks ?? []
        let done = GameTuning.pearlShop.filter { !kept.contains($0.id) && earnsNow($0) }.map(\.id)
        guard !done.isEmpty else { return false }
        save.earnedLooks = kept.union(done)
        return true
    }

    /// Whether this player has bought a look with pearls (on any of their devices).
    var hasBoughtALook: Bool { !(save.ownedLooks ?? []).isEmpty }

    /// Bought, or earned (and kept, even if it's sold now or retired).
    func owns(_ item: PearlItem) -> Bool {
        save.ownedLooks?.contains(item.id) == true || save.earnedLooks?.contains(item.id) == true || earnsNow(item)
    }

    /// The shop's shelf of `kind` (from `catalog`, the shop's): everything but a retired look this player doesn't have.
    func shelf(_ kind: PearlItem.Kind, catalog: [PearlItem] = GameTuning.pearlShop) -> [PearlItem] {
        catalog.filter { $0.kind == kind && (!$0.retired || owns($0)) }
    }

    /// Buys `item` and puts it on, if there are pearls enough, it isn't owned already, and it's on sale `today` (a
    /// limited edition only in its season). Whether it was bought.
    @discardableResult func buy(_ item: PearlItem, now: Date = Date(), today: Date = PearlSeason.today) -> Bool {
        guard !owns(item), item.onSale(today), pearls >= item.price else { return false }
        save.pearlsSpent = (save.pearlsSpent ?? [:]).merging([install: item.price], uniquingKeysWith: +)
        save.ownedLooks = (save.ownedLooks ?? []).union([item.id])
        save.wornLook = ArcadeSave.WornLook(items: wornLook.wearing(item).ids, changed: now.timeIntervalSince1970)
        persist()
        return true
    }

    /// Puts on `look`, as much of it as is owned.
    func wear(_ look: PlayerLook, now: Date = Date()) {
        let ids = look.ids.filter { PearlItem.item($0.value).map(owns) == true }
        guard ids != (save.wornLook?.items ?? [:]) else { return }
        save.wornLook = ArcadeSave.WornLook(items: ids, changed: now.timeIntervalSince1970)
        persist()
    }

    /// Whether the shop has a look the player hasn't seen there yet.
    func isNew(_ item: PearlItem) -> Bool { !(save.seenLooks ?? GameTuning.pearlShopFirstLooks).contains(item.id) }

    /// The shop's `items` seen, so they're no longer marked new.
    func sawLooks(_ items: [PearlItem]) {
        let seen = save.seenLooks ?? GameTuning.pearlShopFirstLooks
        let all = seen.union(items.map(\.id))
        guard all != save.seenLooks else { return }
        save.seenLooks = all
        persist()
    }

    /// The outfit saved in `slot` (from 1), as much of it as is owned: nil while it's empty.
    func outfit(_ slot: Int) -> PlayerLook? {
        save.savedOutfits?[String(slot)].map { PlayerLook(ids: $0.items.filter { PearlItem.item($0.value).map(owns) == true }) }
    }

    /// Saves what's worn now in outfit `slot` (from 1), over whatever was there.
    func saveOutfit(_ slot: Int, now: Date = Date()) {
        var outfits = save.savedOutfits ?? [:]
        outfits[String(slot)] = ArcadeSave.WornLook(items: wornLook.ids, changed: now.timeIntervalSince1970)
        save.savedOutfits = outfits
        persist()
    }

    /// What your fish wears everywhere it swims.
    var look: PlayerLook { wornLook }

    private var wornLook: PlayerLook { PlayerLook(ids: save.wornLook?.items ?? [:]) }

    /// Saves on the device first, then backs up to iCloud, merged with anything there this device hasn't seen yet.
    private func persist() {
        keepEarnedLooks()
        writeLocal()
        syncWithCloud()
    }

    /// Brings in iCloud's progress (another device's, or this player's from before a reinstall) and backs up whatever
    /// iCloud lacks. It only ever adds progress, on either side. Runs at launch, whenever iCloud's copy changes, and
    /// with every save.
    private func syncWithCloud() {
        guard let cloud else { return }
        let theirs = readSave(in: cloud)
        let merged = theirs.map(save.merged(withCloud:)) ?? save
        if merged != save {
            save = merged
            // Another device's progress may have done a look's goal here.
            keepEarnedLooks()
            writeLocal()
        }
        // Only what iCloud lacks is written: a fresh install with nothing to back up doesn't upload an empty save.
        if save != (theirs ?? ArcadeSave()) { write(save, to: cloud) }
    }

    /// iCloud's save, or nil when it has none or one this version can't read. An unreadable one is set aside on the
    /// device and never trusted over this device's progress.
    private func readSave(in cloud: ArcadeCloudStore) -> ArcadeSave? {
        guard let data = cloud.data(forKey: Self.key) else { return nil }
        if let theirs = try? JSONDecoder().decode(ArcadeSave.self, from: data) { return theirs }
        defaults.set(data, forKey: Self.unreadableCloudKey)
        return nil
    }

    private func writeLocal() {
        guard let data = try? JSONEncoder().encode(save) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private func write(_ save: ArcadeSave, to cloud: ArcadeCloudStore) {
        guard let data = try? JSONEncoder().encode(save) else { return }
        cloud.set(data, forKey: Self.key)
    }
}
