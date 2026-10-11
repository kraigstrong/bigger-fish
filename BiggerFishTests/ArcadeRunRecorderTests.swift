#if DEBUG
import Foundation
import Testing
@testable import BiggerFish

struct ArcadeRunRecorderTests {
    private func records(_ url: URL) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
    }

    @Test func streamedLogsSurvivePauseAndFinishOnceWithEventsInOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = ArcadeRunRecorder(directory: directory)
        recorder.event("start", time: 0, simulationTime: 0, fields: ["world": "jelly-bloom", "level": 2])
        recorder.snapshot(time: 0, simulationTime: 0, fields: ["fish": [["id": 0, "radius": 16]]])
        recorder.snapshot(time: 0.05, simulationTime: 0.05, fields: [:]) // throttled
        recorder.event("input", time: 0.1, simulationTime: 0.1, fields: ["holding": true])
        recorder.event("eat", time: 0.2, simulationTime: 0.2, fields: ["predatorID": 1, "preyID": 2])
        recorder.snapshot(time: 0.3, simulationTime: 0.3, fields: [:])
        recorder.checkpoint()
        recorder.waitForWrites()
        let partial = try records(recorder.fileURL)
        #expect(partial.compactMap { $0["type"] as? String } == ["start", "snapshot", "input", "eat", "snapshot"])
        #expect(partial[0]["level"] as? Int == 2)
        recorder.finish(outcome: "lost", time: 0.4, simulationTime: 0.35, fields: ["reason": "Caught in the tentacles."])
        recorder.finish(outcome: "restart", time: 0.5, simulationTime: 0.4)
        recorder.event("bounce", time: 0.6, simulationTime: 0.5)
        recorder.waitForWrites()
        let completed = try records(recorder.fileURL)
        #expect(completed.count == 6)
        #expect(completed.last?["outcome"] as? String == "lost")
        #expect(completed.last?["reason"] as? String == "Caught in the tentacles.")
        #expect(completed.last?["simTime"] as? Double == 0.35)
    }

    @Test func retentionOnlyRemovesOldRunFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for i in 0..<(ArcadeRunRecorder.retainedRuns + 10) {
            try Data().write(to: directory.appendingPathComponent("run-2000-\(i).jsonl"))
        }
        let note = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: note)
        // The hitch log's files keep their own count.
        let hitches = directory.appendingPathComponent("hitches-1999-0.jsonl")
        try Data().write(to: hitches)
        let recorder = ArcadeRunRecorder(directory: directory)
        recorder.finish(outcome: "won", time: 1, simulationTime: 1)
        recorder.waitForWrites()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.filter { $0.lastPathComponent.hasPrefix("run-") }.count == ArcadeRunRecorder.retainedRuns)
        #expect(FileManager.default.fileExists(atPath: note.path))
        #expect(FileManager.default.fileExists(atPath: hitches.path))
        #expect(try records(recorder.fileURL).last?["outcome"] as? String == "won")
    }

    /// The hitch log's file: its own prefix and count, and records with no simulation clock.
    @Test func hitchFilesKeepTheirOwnPrefixAndCount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for i in 0..<5 { try Data().write(to: directory.appendingPathComponent("hitches-2000-\(i).jsonl")) }
        try Data().write(to: directory.appendingPathComponent("run-2000-0.jsonl"))
        let recorder = ArcadeRunRecorder(directory: directory, prefix: "hitches", retained: 3)
        recorder.event("hitch", time: 2.5, fields: ["screen": "settings", "elapsedMs": 40.0])
        recorder.waitForWrites()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(recorder.fileURL.lastPathComponent.hasPrefix("hitches-"))
        #expect(names.filter { $0.hasPrefix("hitches-") }.count == 3 && names.contains("run-2000-0.jsonl"))
        let hitch = try #require(try records(recorder.fileURL).first)
        #expect(hitch["type"] as? String == "hitch" && hitch["time"] as? Double == 2.5 && hitch["simTime"] == nil)
    }
}
#endif
