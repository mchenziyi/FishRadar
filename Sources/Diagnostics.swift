import Foundation

final class Diagnostics {
    let fileURL: URL
    private let limit: UInt64
    private let formatter = ISO8601DateFormatter()
    init(directory: URL? = nil, limit: UInt64 = 5 * 1024 * 1024) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = directory ?? support.appendingPathComponent("FishRadar", isDirectory: true)
        fileURL = folder.appendingPathComponent("diagnostics.jsonl")
        self.limit = limit
    }
    func savePhoto(_ data: Data) throws -> String {
        let fm = FileManager.default
        let folder = fileURL.deletingLastPathComponent().appendingPathComponent("photos", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let files = try fm.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".jpg") }
        guard files.count < 200 else { throw NSError(domain: "FishRadar", code: 1, userInfo: [NSLocalizedDescriptionKey: "照片已达到 200 张上限，请整理照片后继续。 "]) }
        let name = UUID().uuidString + ".jpg"
        let url = folder.appendingPathComponent(name)
        guard fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        return "photos/" + name
    }
    func write(_ type: String, _ values: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
        if size >= limit {
            let previous = fileURL.deletingPathExtension().appendingPathExtension("previous.jsonl")
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
            try fm.moveItem(at: fileURL, to: previous)
        }
        var record = values; record["time"] = formatter.string(from: Date()); record["type"] = type
        var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]); data.append(10)
        if !fm.fileExists(atPath: fileURL.path) { guard fm.createFile(atPath: fileURL.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) } }
        let handle = try FileHandle(forWritingTo: fileURL); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
}
