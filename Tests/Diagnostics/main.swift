import Foundation
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: dir) }
let logger = Diagnostics(directory: dir, limit: 1)
try logger.write("resources", ["cpu_percent": 4.2, "resident_mib": 75])
let first = try Data(contentsOf: logger.fileURL)
let sample = try JSONSerialization.jsonObject(with: first) as! [String: Any]
assert(sample["type"] as? String == "resources")
assert(sample["cpu_percent"] as? Double == 4.2)
try logger.write("trial", ["scenario": "左侧靠近", "result": "漏报"])
assert(FileManager.default.fileExists(atPath: dir.appendingPathComponent("diagnostics.previous.jsonl").path))
let trial = try JSONSerialization.jsonObject(with: Data(contentsOf: logger.fileURL)) as! [String: Any]
assert(trial["type"] as? String == "trial")
print("Diagnostics tests passed")
let fakeJPEG = Data([0xff, 0xd8, 0xff, 0xd9])
let path = try logger.savePhoto(fakeJPEG)
let photoURL = dir.appendingPathComponent(path)
let savedPhoto = try Data(contentsOf: photoURL)
assert(savedPhoto == fakeJPEG)
let attrs = try FileManager.default.attributesOfItem(atPath: photoURL.path)
assert((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)

for _ in 1..<200 {
    _ = try logger.savePhoto(fakeJPEG)
}
do {
    _ = try logger.savePhoto(fakeJPEG)
    assertionFailure("The default limit should stop after 200 photos")
} catch {
    assert(error.localizedDescription.contains("200"))
}
let extra = try logger.savePhoto(fakeJPEG, maximumCount: 201)
assert(FileManager.default.fileExists(atPath: dir.appendingPathComponent(extra).path))
do {
    _ = try logger.savePhoto(fakeJPEG, maximumCount: 201)
    assertionFailure("The configured limit should stop after 201 photos")
} catch {
    assert(error.localizedDescription.contains("201"))
}
do {
    _ = try logger.savePhoto(fakeJPEG, maximumCount: 0)
    assertionFailure("A photo limit must be positive")
} catch {
    assert(error.localizedDescription.contains("正整数"))
}
let photos = try FileManager.default.contentsOfDirectory(atPath: photoURL.deletingLastPathComponent().path)
assert(photos.count == 201 && photos.contains(photoURL.lastPathComponent))
print("Photo storage tests passed")
