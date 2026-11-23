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
print("Photo storage tests passed")
