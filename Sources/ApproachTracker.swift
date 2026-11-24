import Foundation
import CoreGraphics


// Heuristic: associate nearby detections and look for sustained growth in their height.
struct RadarLevels: Equatable {
    var left = 0
    var right = 0
}

func shouldCaptureAutomaticPhoto(previous: RadarLevels?, current: RadarLevels?) -> Bool {
    guard let previous, let current else { return false }
    return current.left > previous.left || current.right > previous.right
}

func shouldSwitchToWorkApp(previous: RadarLevels?, current: RadarLevels?) -> Bool {
    guard let current, current.left >= 2 || current.right >= 2 else { return false }
    return (previous?.left ?? 0) < 2 && (previous?.right ?? 0) < 2
}

func mirrorZone(_ rect: CGRect) -> CGRect {
    CGRect(x: 1 - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
}

func includesDetection(_ box: CGRect, effective: CGRect?, ignore: CGRect?) -> Bool {
    let center = CGPoint(x: box.midX, y: box.midY)
    return (effective?.contains(center) ?? true) && !(ignore?.contains(center) ?? false)
}

func detectionInterval(lastAlert: TimeInterval?, now: TimeInterval) -> TimeInterval {
    guard let lastAlert, now - lastAlert < 2 else { return 0.4 }
    return 0.2
}

struct ApproachTracker {
    private struct Sample { let time: TimeInterval; let box: CGRect }
    private struct Track {
        var samples: [Sample]
        var anchor: CGRect
        var lastMovement: TimeInterval
    }
    var stationarySeconds: TimeInterval = 5
    var sensitivity: Double = 1
    var focusZone: CGRect?
    private var tracks: [Track] = []
    private var leftUntil: TimeInterval = 0
    private var rightUntil: TimeInterval = 0
    private var heldLeft = 0
    private var heldRight = 0

    mutating func update(_ boxes: [CGRect], at time: TimeInterval) -> RadarLevels {
        tracks = tracks.filter { time - ($0.samples.last?.time ?? 0) <= 1.2 }
        var used = Set<Int>()
        if time >= leftUntil { heldLeft = 0 }
        if time >= rightUntil { heldRight = 0 }
        var presentLeft = false
        var presentRight = false
        for box in boxes {
            let match = tracks.indices.filter { !used.contains($0) }.min { a, b in
                distance(tracks[a].samples.last!.box, box) < distance(tracks[b].samples.last!.box, box)
            }
            let index: Int
            if let match = match, distance(tracks[match].samples.last!.box, box) < 0.2 {
                index = match
            } else {
                tracks.append(Track(samples: [], anchor: box, lastMovement: time))
                index = tracks.count - 1
            }
            used.insert(index)
            if distance(tracks[index].anchor, box) > 0.04 || abs(tracks[index].anchor.height - box.height) > 0.04 {
                tracks[index].anchor = box
                tracks[index].lastMovement = time
            }
            if time - tracks[index].lastMovement < stationarySeconds {
                if box.midX >= 0.42 { presentLeft = true }
                if box.midX <= 0.58 { presentRight = true }
            }
            tracks[index].samples.append(Sample(time: time, box: box))
            tracks[index].samples.removeAll { time - $0.time > 3 }
            let history = tracks[index].samples
            let priority = focusZone?.contains(CGPoint(x: box.midX, y: box.midY)) ?? false
            let growth = 1 + (priority ? 0.10 : 0.18) / sensitivity
            if history.count >= 3, let first = history.first,
               history.suffix(2).allSatisfy({ $0.box.height > first.box.height * growth }),
               box.height - first.box.height > 0.025 {
                let level = box.height > first.box.height * 1.45 ? 3 : 2
                // Preview is horizontally mirrored: raw right appears on the user's left.
                if box.midX >= 0.42 { heldLeft = max(heldLeft, level); leftUntil = time + 4 }
                if box.midX <= 0.58 { heldRight = max(heldRight, level); rightUntil = time + 4 }
            }
        }
        return RadarLevels(left: max(heldLeft, presentLeft ? 1 : 0), right: max(heldRight, presentRight ? 1 : 0))
    }

    private func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }
}
