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
        let recorder = ArcadeRunRecorder(directory: directory)
        recorder.finish(outcome: "won", time: 1, simulationTime: 1)
        recorder.waitForWrites()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.filter { $0.pathExtension == "jsonl" }.count == ArcadeRunRecorder.retainedRuns)
        #expect(FileManager.default.fileExists(atPath: note.path))
        #expect(try records(recorder.fileURL).last?["outcome"] as? String == "won")
    }
}
#endif
