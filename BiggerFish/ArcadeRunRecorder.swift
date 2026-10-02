#if DEBUG
import Foundation

/// Local debug builds only. Streaming files survive unfinished runs and never leave the phone
/// until the developer explicitly pulls them. No gameplay or Math Reef analytics dependency.
final class ArcadeRunRecorder {
    static let snapshotSeconds: Double = 0.2
    static let retainedRuns = 30
    let fileURL: URL
    private let queue = DispatchQueue(label: "biggerFish.runRecorder", qos: .utility)
    private var handle: FileHandle?
    private var finished = false
    private var lastSnapshot = -Double.infinity
    private var lastSync = 0.0

    static func makeDefault() -> ArcadeRunRecorder? {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !ProcessInfo.processInfo.arguments.contains("-arcadeDisableRunRecording"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return ArcadeRunRecorder(directory: documents.appendingPathComponent("ArcadeRuns", isDirectory: true))
    }

    init(directory: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        fileURL = directory.appendingPathComponent("run-\(timestamp)-\(UUID().uuidString.prefix(8)).jsonl")
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                handle = try FileHandle(forWritingTo: fileURL)
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
                for old in files.dropFirst(Self.retainedRuns) where old != fileURL {
                    try FileManager.default.removeItem(at: old)
                }
                print("[ArcadeRun] Recording \(fileURL.lastPathComponent)")
            } catch { print("[ArcadeRun] Cannot start recording: \(error)") }
        }
    }

    func event(_ name: String, time: Double, simulationTime: Double, fields: [String: Any] = [:]) {
        guard !finished else { return }
        append(type: name, time: time, simulationTime: simulationTime, fields: fields)
    }

    func wantsSnapshot(time: Double) -> Bool { !finished && time - lastSnapshot >= Self.snapshotSeconds }

    func snapshot(time: Double, simulationTime: Double, fields: [String: Any], force: Bool = false) {
        guard !finished, force || time - lastSnapshot >= Self.snapshotSeconds else { return }
        lastSnapshot = time
        append(type: "snapshot", time: time, simulationTime: simulationTime, fields: fields)
        if time - lastSync >= 2 {
            lastSync = time
            checkpoint()
        }
    }

    func checkpoint() {
        queue.async { [self] in
            do { try handle?.synchronize() }
            catch { print("[ArcadeRun] Cannot flush recording: \(error)") }
        }
    }

    func finish(outcome: String, time: Double, simulationTime: Double, fields: [String: Any] = [:]) {
        guard !finished else { return }
        var summary = fields
        summary["outcome"] = outcome
        append(type: "end", time: time, simulationTime: simulationTime, fields: summary)
        finished = true
        queue.async { [self] in
            do { try handle?.synchronize(); try handle?.close() }
            catch { print("[ArcadeRun] Cannot finish recording: \(error)") }
            handle = nil
            print("[ArcadeRun] \(outcome) after \(String(format: "%.1f", time))s — \(fileURL.lastPathComponent)")
        }
    }

    private func append(type: String, time: Double, simulationTime: Double, fields: [String: Any]) {
        var entry = fields
        entry["type"] = type
        entry["time"] = time
        entry["simTime"] = simulationTime
        queue.async { [self, entry] in
            guard let handle else { return }
            do {
                var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
                data.append(0x0a)
                try handle.write(contentsOf: data)
            } catch { print("[ArcadeRun] Cannot write recording: \(error)") }
        }
    }

    /// A deterministic barrier for tests; normal play never waits on the writer.
    func waitForWrites() { queue.sync {} }
}
#endif
