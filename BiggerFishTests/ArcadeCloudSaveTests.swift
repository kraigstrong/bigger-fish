import Combine
import Foundation
import Testing
@testable import BiggerFish

/// A stand-in for iCloud's key-value storage, so tests never touch the real one.
final class FakeCloud: ArcadeCloudStore {
    var values: [String: Data] = [:]
    private(set) var writes = 0

    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) {
        values[key] = data
        writes += 1
    }
    func synchronize() -> Bool { true }

    /// The save backed up here, if it reads.
    var save: ArcadeSave? { values[ArcadeProgress.key].flatMap { try? JSONDecoder().decode(ArcadeSave.self, from: $0) } }

    /// The backed-up save's top-level JSON object, exactly as written.
    var json: [String: Any]? {
        values[ArcadeProgress.key].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// iCloud's copy changing from outside the app (another device's backup, the first download after an install, or a
    /// change of Apple ID), then telling the app, as the real store does.
    func change(to json: String?, reason: Int = NSUbiquitousKeyValueStoreServerChange) {
        values[ArcadeProgress.key] = json.map { Data($0.utf8) }
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: self,
            userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: reason,
                       NSUbiquitousKeyValueStoreChangedKeysKey: [ArcadeProgress.key]])
    }
}

/// Progress backed up to iCloud (kraigstrong/bigger-fish#96). Losing progress would be a game killer, so syncing must
/// only ever add progress, every save must still load, and nothing this version doesn't understand may be dropped.
struct ArcadeCloudSaveTests {
    /// Exactly what 0.1 wrote.
    static let firstVersion = #"{"clearedLevels":["shallow-reef.1","shallow-reef.2"],"bestTimes":{"shallow-reef.1":21.5},"hasSeenJellyLesson":false}"#

    /// A device: its own saved state, and the iCloud it backs up to (nil for none).
    private func device(_ json: String? = nil, cloud: FakeCloud?) -> (ArcadeProgress, UserDefaults) {
        let defaults = UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!
        if let json { defaults.set(Data(json.utf8), forKey: ArcadeProgress.key) }
        return (ArcadeProgress(defaults: defaults, cloud: cloud), defaults)
    }

    private func save(_ json: String) throws -> ArcadeSave {
        try JSONDecoder().decode(ArcadeSave.self, from: Data(json.utf8))
    }

    /// The save on the device, as stored.
    private func stored(_ defaults: UserDefaults) -> ArcadeSave? {
        defaults.data(forKey: ArcadeProgress.key).flatMap { try? JSONDecoder().decode(ArcadeSave.self, from: $0) }
    }

    private func storedJSON(_ defaults: UserDefaults) -> [String: Any]? {
        defaults.data(forKey: ArcadeProgress.key).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    // MARK: Merge rules

    /// A field without a key is never saved, and a key without a merge rule doesn't compile (`merged(withCloud:)`
    /// switches over every key), so this catches a new field that would be dropped by a save or a sync.
    @Test func everyFieldIsSavedAndMerged() {
        let fields = Set(Mirror(reflecting: ArcadeSave()).children.compactMap(\.label))
        #expect(fields == Set(ArcadeSave.CodingKeys.allCases.map(\.stringValue) + ["laterFields"]))
    }

    @Test func clearedLevelsAreUnited() throws {
        let mine = try save(#"{"clearedLevels":["shallow-reef.1","shallow-reef.2"]}"#)
        let theirs = try save(#"{"clearedLevels":["shallow-reef.2","jelly-bloom.1"]}"#)
        #expect(mine.merged(withCloud: theirs).clearedLevels == ["shallow-reef.1", "shallow-reef.2", "jelly-bloom.1"])
        // An empty side never un-clears anything.
        #expect(mine.merged(withCloud: ArcadeSave()).clearedLevels == mine.clearedLevels)
        #expect(ArcadeSave().merged(withCloud: theirs).clearedLevels == theirs.clearedLevels)
    }

    @Test func eachLevelKeepsTheFasterBestTime() throws {
        let mine = try save(#"{"bestTimes":{"shallow-reef.1":30,"shallow-reef.2":41.5,"kelp-forest.3":50}}"#)
        let theirs = try save(#"{"bestTimes":{"shallow-reef.1":25.25,"shallow-reef.2":44,"jelly-bloom.1":60}}"#)
        let expected = ["shallow-reef.1": 25.25, "shallow-reef.2": 41.5, "kelp-forest.3": 50, "jelly-bloom.1": 60]
        #expect(mine.merged(withCloud: theirs).bestTimes == expected)
        #expect(theirs.merged(withCloud: mine).bestTimes == expected)
    }

    @Test func aLessonOrTutorialSeenOnEitherSideStaysSeen() throws {
        let saw = try save(#"{"hasSeenJellyLesson":true,"hasSeenTutorial":true,"hasSeenOpenWaterTutorial":true,"hasSeenShopTutorial":true}"#)
        let notYet = try save(#"{"hasSeenJellyLesson":false,"hasSeenTutorial":false,"hasSeenOpenWaterTutorial":false,"hasSeenShopTutorial":false}"#)
        let before = try save(#"{"clearedLevels":[]}"#)  // From before the tutorials existed: no field at all.
        let seen = { (save: ArcadeSave) in [save.hasSeenTutorial, save.hasSeenOpenWaterTutorial, save.hasSeenShopTutorial] }
        for (mine, theirs) in [(saw, notYet), (notYet, saw), (saw, before), (before, saw)] {
            let merged = mine.merged(withCloud: theirs)
            #expect(merged.hasSeenJellyLesson && seen(merged) == [true, true, true])
        }
        #expect(seen(notYet.merged(withCloud: before)) == [false, false, false])
        #expect(seen(before.merged(withCloud: notYet)) == [false, false, false])
        // Neither side has the field: it stays out of the save, as it always has.
        #expect(seen(before.merged(withCloud: before)) == [nil, nil, nil] && !before.merged(withCloud: before).hasSeenJellyLesson)
    }

    @Test func seenConqueredScreensAreUnited() throws {
        let mine = try save(#"{"seenUnlocks":["shallow-reef"]}"#)
        let theirs = try save(#"{"seenUnlocks":["jelly-bloom","kelp-forest"]}"#)
        let before = ArcadeSave()  // From before conquered screens were remembered.
        #expect(mine.merged(withCloud: theirs).seenUnlocks == ["shallow-reef", "jelly-bloom", "kelp-forest"])
        #expect(mine.merged(withCloud: before).seenUnlocks == ["shallow-reef"])
        #expect(before.merged(withCloud: theirs).seenUnlocks == ["jelly-bloom", "kelp-forest"])
        #expect(before.merged(withCloud: before).seenUnlocks == nil)
    }

    /// Two devices merging each other's saves come out the same, however often they merge.
    @Test func mergingIsTheSameEitherWayAndRepeatable() throws {
        let saves = try [
            ArcadeSave(),
            save(Self.firstVersion),
            save(#"{"clearedLevels":["shallow-reef.2","jelly-bloom.10"],"bestTimes":{"shallow-reef.1":19,"jelly-bloom.10":80},"hasSeenJellyLesson":true,"seenUnlocks":["jelly-bloom"],"hasSeenTutorial":true}"#),
            save(#"{"clearedLevels":["midnight-zone.4"],"bestTimes":{"shallow-reef.1":23},"seenUnlocks":[],"hasSeenTutorial":false}"#),
        ]
        for a in saves {
            #expect(a.merged(withCloud: a) == a)
            for b in saves {
                let ab = a.merged(withCloud: b)
                #expect(ab == b.merged(withCloud: a))
                #expect(ab.merged(withCloud: b) == ab && ab.merged(withCloud: a) == ab)
                #expect(a.clearedLevels.isSubset(of: ab.clearedLevels) && b.clearedLevels.isSubset(of: ab.clearedLevels))
            }
        }
    }

    // MARK: Saves from other versions

    /// A field from a later version (pearls, say) is kept exactly as it was, whatever its shape, so an older version
    /// saving or backing up never drops it.
    @Test func fieldsFromALaterVersionAreKeptExactly() throws {
        let later = #"{"clearedLevels":["kelp-forest.1"],"bestTimes":{"kelp-forest.1":30.5},"hasSeenJellyLesson":true,"pearls":12,"ratio":0.25,"title":"Captain","flags":[true,false,null],"nested":{"deep":{"list":[1,2.5,"three"]}},"nothing":null}"#
        let loaded = try save(later)
        #expect(loaded.isCleared("kelp-forest.1") && loaded.bestTimes["kelp-forest.1"] == 30.5)
        #expect(loaded.laterFields["pearls"] == .integer(12) && loaded.laterFields["ratio"] == .number(0.25))
        #expect(loaded.laterFields["title"] == .string("Captain") && loaded.laterFields["nothing"] == .null)
        #expect(loaded.laterFields["flags"] == .array([.bool(true), .bool(false), .null]))
        #expect(loaded.laterFields["nested"] == .object(["deep": .object(["list": .array([.integer(1), .number(2.5), .string("three")])])]))
        #expect(Set(loaded.laterFields.keys) == ["pearls", "ratio", "title", "flags", "nested", "nothing"])

        // Written back, it's the same JSON object, key for key.
        let original = try JSONSerialization.jsonObject(with: Data(later.utf8)) as! NSDictionary
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as! NSDictionary
        #expect(original == written)
        #expect(try JSONDecoder().decode(ArcadeSave.self, from: JSONEncoder().encode(loaded)) == loaded)

        // Saved on a device with no iCloud, too.
        let (progress, defaults) = device(later, cloud: nil)
        progress.clear(.kelpForest, 1, seconds: 40)
        let saved = try #require(storedJSON(defaults))
        #expect(saved["pearls"] as? Int == 12 && (saved["nested"] as? [String: Any])?["deep"] != nil)
        #expect(saved["nothing"] is NSNull && (saved["flags"] as? [Any])?.count == 3)
        #expect(stored(defaults)?.isCleared("kelp-forest.2") == true)
    }

    /// An older version merging a later version's backup, and backing up the result, keeps every field it doesn't know.
    @Test func backingUpALaterVersionsSaveKeepsItsFields() throws {
        let cloud = FakeCloud()
        cloud.values[ArcadeProgress.key] = Data(#"{"clearedLevels":["jelly-bloom.1"],"bestTimes":{},"hasSeenJellyLesson":true,"pearls":7,"outfits":{"hat":"red"}}"#.utf8)
        let (progress, defaults) = device(Self.firstVersion, cloud: cloud)
        // This device's levels went up, iCloud's came down, and so did the fields it doesn't know.
        let backup = try #require(cloud.json)
        #expect(Set(backup["clearedLevels"] as? [String] ?? []) == ["shallow-reef.1", "shallow-reef.2", "jelly-bloom.1"])
        #expect(backup["pearls"] as? Int == 7 && (backup["outfits"] as? [String: String]) == ["hat": "red"])
        #expect(storedJSON(defaults)?["pearls"] as? Int == 7)
        // And it keeps them through later saves.
        progress.clear(.shallowReef, 2, seconds: 33)
        #expect(cloud.json?["pearls"] as? Int == 7 && storedJSON(defaults)?["outfits"] != nil)
        #expect(cloud.save?.isCleared("shallow-reef.3") == true)
    }

    /// Fields this version doesn't know never change here, so iCloud's (the latest any device wrote) wins a
    /// difference, and a field only one side has is kept.
    @Test func laterFieldsOnBothSidesKeepICloudsValue() throws {
        let mine = try save(#"{"pearls":5,"badge":"gold"}"#)
        let theirs = try save(#"{"pearls":9,"hat":"red"}"#)
        let merged = mine.merged(withCloud: theirs)
        #expect(merged.laterFields == ["pearls": .integer(9), "badge": .string("gold"), "hat": .string("red")])
    }

    /// The real 0.1 save on this device and a newer one in iCloud (or the other way round) merge into everything both
    /// have, on the device and in iCloud alike.
    @Test func aFirstVersionSaveAndANewerOneMerge() throws {
        let newer = #"{"clearedLevels":["shallow-reef.2","shallow-reef.10","jelly-bloom.1"],"bestTimes":{"shallow-reef.1":19.0,"shallow-reef.10":55},"hasSeenJellyLesson":true,"seenUnlocks":["shallow-reef"],"hasSeenTutorial":true,"announcedWorlds":["jelly-bloom"]}"#
        var expected = try save(newer)
        expected.clearedLevels.insert("shallow-reef.1")
        for (local, remote) in [(Self.firstVersion, newer), (newer, Self.firstVersion)] {
            let cloud = FakeCloud()
            cloud.values[ArcadeProgress.key] = Data(remote.utf8)
            let (progress, defaults) = device(local, cloud: cloud)
            #expect(progress.save == expected)
            #expect(progress.save.bestTimes["shallow-reef.1"] == 19 && progress.unseenUnlock == nil && !progress.needsTutorial(.adventure))
            #expect(stored(defaults) == expected && cloud.save == expected)
            // It reloads the same, with or without iCloud.
            #expect(ArcadeProgress(defaults: defaults, cloud: nil).save == expected)
            #expect(ArcadeProgress(defaults: defaults, cloud: cloud).save == expected)
        }
    }

    // MARK: Unreadable iCloud saves

    /// An iCloud save that can't be read is ignored, never trusted over the device's progress: it's set aside on the
    /// device, and the device's progress is backed up in its place.
    @Test func anUnreadableICloudSaveIsIgnored() throws {
        for unreadable in ["not a save", "[1,2,3]", "\"a string\"", ""] {
            let cloud = FakeCloud()
            cloud.values[ArcadeProgress.key] = Data(unreadable.utf8)
            let (progress, defaults) = device(Self.firstVersion, cloud: cloud)
            #expect(progress.save == (try save(Self.firstVersion)))
            #expect(stored(defaults) == (try save(Self.firstVersion)))
            #expect(defaults.data(forKey: ArcadeProgress.unreadableCloudKey) == Data(unreadable.utf8))
            #expect(cloud.save == (try save(Self.firstVersion)))
        }
        // A field of the wrong type in iCloud loses only iCloud's copy of that field: the device keeps its own.
        let cloud = FakeCloud()
        cloud.values[ArcadeProgress.key] = Data(#"{"clearedLevels":["jelly-bloom.1"],"bestTimes":"oops"}"#.utf8)
        let (progress, _) = device(Self.firstVersion, cloud: cloud)
        #expect(progress.save.bestTimes == ["shallow-reef.1": 21.5] && progress.isCleared(.jellyBloom, 0))
        #expect(cloud.save?.bestTimes == ["shallow-reef.1": 21.5])
    }

    /// An unreadable save on the device is kept aside as it always was, and iCloud brings the progress back.
    @Test func iCloudRestoresProgressOverAnUnreadableLocalSave() throws {
        let cloud = FakeCloud()
        cloud.values[ArcadeProgress.key] = Data(Self.firstVersion.utf8)
        let (progress, defaults) = device("bad save", cloud: cloud)
        #expect(progress.isCleared(.shallowReef, 1))
        #expect(defaults.data(forKey: ArcadeProgress.unreadableKey) == Data("bad save".utf8))
        #expect(stored(defaults) == (try save(Self.firstVersion)))
    }

    // MARK: Installs, devices, and accounts

    /// Delete the game, reinstall it, and the progress comes back from iCloud: no tutorial, every level still cleared.
    @Test func aReinstallGetsItsProgressBack() throws {
        let cloud = FakeCloud()
        let (first, _) = device(cloud: cloud)
        first.sawTutorial(.adventure)
        first.clear(.shallowReef, 0, seconds: 31)
        first.clear(.shallowReef, 1, seconds: 28)
        first.sawJellyLesson()

        let (reinstalled, defaults) = device(cloud: cloud)
        #expect(reinstalled.save == first.save && stored(defaults) == first.save)
        #expect(!reinstalled.needsTutorial(.adventure) && reinstalled.nextLevel(in: .shallowReef) == 2)
    }

    /// A fresh install with nothing to back up writes nothing: an empty save never goes up to iCloud.
    @Test func aFreshInstallUploadsNothing() {
        let cloud = FakeCloud()
        let (progress, _) = device(cloud: cloud)
        #expect(cloud.writes == 0 && cloud.values.isEmpty && progress.needsTutorial(.adventure))
        progress.sawTutorial(.adventure)
        #expect(cloud.save?.hasSeenTutorial == true)
    }

    /// Two devices on one Apple ID, sharing iCloud: each save merges in the other's before backing up, and when iCloud
    /// keeps only one device's write (the last one wins), the other merges it back in on hearing of the change.
    @Test @MainActor func twoDevicesEndUpWithEverything() async throws {
        let cloud = FakeCloud()
        let (phone, _) = device(cloud: cloud)
        let (pad, _) = device(cloud: cloud)
        phone.clear(.shallowReef, 0, seconds: 30)
        pad.clear(.jellyBloom, 0, seconds: 45)
        #expect(cloud.save?.clearedLevels == ["shallow-reef.1", "jelly-bloom.1"])

        // The pad's backup overwrites a newer one from the phone that hadn't reached it.
        phone.clear(.shallowReef, 1, seconds: 29)
        let stale = try JSONEncoder().encode(pad.save)
        cloud.change(to: String(decoding: stale, as: UTF8.self))
        // The phone hears of it, keeps its level, and backs up everything again.
        try await settle { phone.isCleared(.shallowReef, 1) && cloud.save?.isCleared("shallow-reef.2") == true }
        #expect(cloud.save?.clearedLevels == ["shallow-reef.1", "shallow-reef.2", "jelly-bloom.1"])
        // The pad hears of that, and has it all too.
        cloud.change(to: String(decoding: cloud.values[ArcadeProgress.key]!, as: UTF8.self))
        try await settle { pad.isCleared(.shallowReef, 1) }
        #expect(pad.save == phone.save)
    }

    /// Another device's progress arriving merges in and is published, so the maps redraw with it.
    @Test @MainActor func anExternalChangeMergesAndPublishes() async throws {
        let cloud = FakeCloud()
        let (progress, defaults) = device(Self.firstVersion, cloud: cloud)
        var published: [ArcadeSave] = []
        let watching = progress.$save.dropFirst().sink { published.append($0) }
        defer { watching.cancel() }

        cloud.change(to: #"{"clearedLevels":["jelly-bloom.1","jelly-bloom.2"],"bestTimes":{"shallow-reef.1":18},"hasSeenJellyLesson":true}"#)
        try await settle { progress.isCleared(.jellyBloom, 1) }
        #expect(progress.isCleared(.shallowReef, 1) && progress.isCleared(.jellyBloom, 1))
        #expect(progress.save.bestTimes["shallow-reef.1"] == 18 && progress.save.hasSeenJellyLesson)
        #expect(published.last == progress.save)
        #expect(stored(defaults) == progress.save && cloud.save == progress.save)

        // A change that brings nothing new publishes nothing, and what iCloud lost goes back up.
        let (count, writes) = (published.count, cloud.writes)
        cloud.change(to: #"{"clearedLevels":["shallow-reef.1"]}"#)
        try await settle { cloud.writes > writes }
        #expect(published.count == count)
        #expect(cloud.save == progress.save)
    }

    /// Switching Apple ID, or signing out, never wipes this device's progress: it merges into whatever the new account
    /// has. (A different Apple ID's progress merging into this device's is accepted.)
    @Test @MainActor func anAccountChangeNeverWipesProgress() async throws {
        let cloud = FakeCloud()
        let (progress, defaults) = device(Self.firstVersion, cloud: cloud)
        let mine = progress.save

        // Signed out, or a new account with nothing in it: iCloud's copy is gone.
        cloud.change(to: nil, reason: NSUbiquitousKeyValueStoreAccountChange)
        try await settle { cloud.save != nil }
        #expect(progress.save == mine && stored(defaults) == mine && cloud.save == mine)

        // Another account with progress of its own: the two merge.
        cloud.change(to: #"{"clearedLevels":["kelp-forest.1"],"bestTimes":{"kelp-forest.1":40}}"#,
                     reason: NSUbiquitousKeyValueStoreAccountChange)
        try await settle { progress.isCleared(.kelpForest, 0) }
        #expect(mine.clearedLevels.isSubset(of: progress.save.clearedLevels) && progress.save.bestTimes["shallow-reef.1"] == 21.5)
        #expect(cloud.save == progress.save && stored(defaults) == progress.save)

        // The first download after an install merges the same way.
        cloud.change(to: #"{"clearedLevels":["midnight-zone.1"]}"#, reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        try await settle { progress.isCleared(.midnightZone, 0) }
        #expect(progress.isCleared(.kelpForest, 0) && progress.isCleared(.shallowReef, 1))
    }

    // MARK: What removes progress, and what never syncs

    /// Resetting a world (Debug Tuning > Players) replaces iCloud's copy rather than merging with it, or iCloud would
    /// bring the levels straight back. Everything else in iCloud stays.
    @Test @MainActor func aResetReplacesICloudsCopy() async throws {
        let cloud = FakeCloud()
        cloud.values[ArcadeProgress.key] = Data(#"{"clearedLevels":["shallow-reef.3","midnight-zone.1"],"bestTimes":{"shallow-reef.3":33,"midnight-zone.1":50},"pearls":3}"#.utf8)
        let (progress, defaults) = device(Self.firstVersion, cloud: cloud)
        progress.reset(.shallowReef)
        #expect(progress.save.clearedLevels == ["midnight-zone.1"] && progress.save.bestTimes == ["midnight-zone.1": 50])
        #expect(cloud.save == progress.save && stored(defaults) == progress.save)
        #expect(cloud.json?["pearls"] as? Int == 3)
        // Syncing again, at the next launch or a change, doesn't bring the levels back.
        #expect(ArcadeProgress(defaults: defaults, cloud: cloud).save == progress.save)
        cloud.change(to: String(decoding: cloud.values[ArcadeProgress.key]!, as: UTF8.self))
        try await settle { true }
        #expect(!progress.isCleared(.shallowReef, 0) && progress.save.clearedLevels == ["midnight-zone.1"])
    }

    /// Only the player's real save, in standard defaults, is backed up. A Debug playtest's save and a store capture's
    /// staged one never are, and test runs never touch iCloud at all.
    @Test func onlyTheRealSaveIsBackedUp() {
        let cloud = FakeCloud()
        #expect(ArcadeProgress.backup(for: .standard, iCloud: cloud) === cloud)
        #expect(ArcadeProgress.backup(for: UserDefaults(suiteName: ArcadePlaytest.suiteName)!, iCloud: cloud) == nil)
        #expect(ArcadeProgress.backup(for: UserDefaults(suiteName: StoreCapture.suiteName)!, iCloud: cloud) == nil)
        #expect(ArcadeProgress.backup(for: UserDefaults(suiteName: "biggerFish.tests.\(UUID().uuidString)")!, iCloud: cloud) == nil)
        #expect(ArcadeProgress.iCloud == nil)
    }

    /// Without iCloud (signed out, or turned off for the game, when its storage stays on the device and starts empty),
    /// the game plays exactly as it did before backup existed.
    @Test func withoutICloudNothingChanges() throws {
        let (alone, aloneDefaults) = device(Self.firstVersion, cloud: nil)
        let (synced, syncedDefaults) = device(Self.firstVersion, cloud: FakeCloud())
        func play(_ progress: ArcadeProgress) {
            progress.clear(.shallowReef, 2, seconds: 40)
            progress.clear(.shallowReef, 2, seconds: 35)
            progress.sawJellyLesson()
            progress.sawTutorial(.adventure)
            progress.sawUnlock(.shallowReef)
            progress.reset(.jellyBloom)
        }
        play(alone)
        play(synced)
        #expect(alone.save == synced.save)
        #expect(stored(aloneDefaults) == stored(syncedDefaults))
        #expect(ArcadeProgress(defaults: aloneDefaults, cloud: nil).save == alone.save)
    }

    /// Waits for the main queue to deliver iCloud's change notification, however it's scheduled.
    @MainActor private func settle(_ done: () -> Bool) async throws {
        for _ in 0..<100 where !done() { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(20))
    }
}

private extension ArcadeSave {
    func isCleared(_ id: String) -> Bool { clearedLevels.contains(id) }
}
