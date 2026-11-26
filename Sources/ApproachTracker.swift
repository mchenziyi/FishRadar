import Foundation
import CoreGraphics


struct RadarLevels: Equatable {
    var left = 0
    var right = 0

    mutating func include(_ level: Int, at midX: CGFloat) {
        // Preview is horizontally mirrored: raw right appears on the user's left.
        if midX >= 0.42 { left = max(left, level) }
        if midX <= 0.58 { right = max(right, level) }
    }
}

struct DistanceComparison: Equatable {
    let current: RadarLevels
    let geometry: RadarLevels
    let viewUnstable: Bool
    let personCount: Int
    let clippedCount: Int
    let redStates: [DistanceEvidence.State]
}

struct DistanceEvidence {
    enum RedReason: String {
        case confirmed, needsMoreFrames = "needs_more_frames", belowThreshold = "below_threshold"
        case strongFirstFrame = "strong_first_frame"
        case widthLimited = "width_limited", frameEdge = "frame_edge", edgeHold = "edge_hold"
        case stationary, repeatedSmallBox = "repeated_small_box", viewUnstable = "view_unstable"
    }

    struct State: Equatable {
        let current: RedReason
        let candidate: RedReason
        let currentLevel: Int
        let candidateLevel: Int
        let seenInFrame: Bool
        let clipped: Bool
    }

    let box: CGRect
    let state: State

    var logValues: [String: Any] {
        [
            "screen_x": Double(1 - box.midX), "height": Double(box.height), "width": Double(box.width),
            "seen_in_frame": state.seenInFrame, "clipped": state.clipped,
            "current_level": state.currentLevel, "candidate_level": state.candidateLevel,
            "current_red_reason": state.current.rawValue, "candidate_red_reason": state.candidate.rawValue,
        ]
    }
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
    static let redSizeThreshold: CGFloat = 0.42

    private struct Sample { let time: TimeInterval; let box: CGRect }
    private struct Track {
        var samples: [Sample]
        var anchor: CGRect
        var lastMovement: TimeInterval
        let firstSeen: TimeInterval
        var remembersSmallBox: Bool
        var reappearances = 0
        var lastUnclipped: (time: TimeInterval, level: Int)?
        var geometry = GeometryDistance()

        static func canRemember(_ box: CGRect) -> Bool {
            box.width <= 0.10 && ApproachTracker.apparentSize(box) <= 0.20
        }

        func matchesSmallBox(_ box: CGRect) -> Bool {
            remembersSmallBox && Self.canRemember(box)
                && hypot(anchor.midX - box.midX, anchor.midY - box.midY) <= 0.02
                && abs(anchor.height - box.height) <= 0.025
                && abs(anchor.width - box.width) <= 0.025
        }
    }
    var stationarySeconds: TimeInterval = 5
    var sensitivity: Double = 1
    var focusZone: CGRect?
    private var tracks: [Track] = []

    mutating func update(_ boxes: [CGRect], at time: TimeInterval, viewUnstable: Bool = false) -> RadarLevels {
        update(boxes, at: time, compareGeometry: false, viewUnstable: viewUnstable).current
    }

    mutating func resetGeometry() {
        for index in tracks.indices { tracks[index].geometry = GeometryDistance() }
    }

    mutating func update(_ boxes: [CGRect], at time: TimeInterval, compareGeometry: Bool,
                         viewUnstable: Bool = false) -> (current: RadarLevels, geometry: RadarLevels?, evidence: [DistanceEvidence]) {
        if viewUnstable {
            if compareGeometry { resetGeometry() }
            for index in tracks.indices {
                tracks[index].lastUnclipped = nil
                tracks[index].remembersSmallBox = false
            }
        }
        // Keep small stationary candidates across detector dropouts, with stricter matching when dormant.
        tracks.removeAll { time - $0.samples.last!.time > ($0.remembersSmallBox ? 60 : 1.2) }
        var used = Set<Int>()
        for box in boxes {
            let match = tracks.indices.filter {
                !used.contains($0) && (time - tracks[$0].samples.last!.time <= 1.2 || tracks[$0].matchesSmallBox(box))
            }.min { a, b in
                distance(tracks[a].samples.last!.box, box) < distance(tracks[b].samples.last!.box, box)
            }
            let index: Int
            if let match = match, distance(tracks[match].samples.last!.box, box) < 0.2 {
                index = match
            } else {
                tracks.append(Track(samples: [], anchor: box, lastMovement: time, firstSeen: time,
                                    remembersSmallBox: !viewUnstable && Track.canRemember(box)))
                index = tracks.count - 1
            }
            used.insert(index)
            if let last = tracks[index].samples.last, time - last.time > 0.6 {
                tracks[index].lastUnclipped = nil
                tracks[index].geometry = GeometryDistance()
                if tracks[index].matchesSmallBox(box) {
                    tracks[index].reappearances += 1
                }
                if time - last.time > 1.2 {
                    tracks[index].samples.removeAll()
                    if last.time - tracks[index].lastMovement < stationarySeconds {
                        tracks[index].lastMovement = time
                    }
                }
            }
            if tracks[index].remembersSmallBox && !tracks[index].matchesSmallBox(box) {
                tracks[index].remembersSmallBox = false
                tracks[index].lastMovement = time
            }
            if distance(tracks[index].anchor, box) > 0.04 || abs(tracks[index].anchor.height - box.height) > 0.04 {
                tracks[index].anchor = box
                tracks[index].lastMovement = time
            }
            if compareGeometry && !viewUnstable {
                let priority = focusZone?.contains(CGPoint(x: box.midX, y: box.midY)) ?? false
                let growth = (priority ? 0.10 : 0.18) / sensitivity
                tracks[index].geometry.update(box, at: time, growth: growth)
            }
            tracks[index].samples.append(Sample(time: time, box: box))
            tracks[index].samples.removeAll { time - $0.time > 3 }
        }
        var levels = RadarLevels()
        var geometryLevels = RadarLevels()
        var evidence: [DistanceEvidence] = []
        for index in tracks.indices {
            let track = tracks[index]
            guard let last = track.samples.last, time - last.time <= 0.6 else { continue }
            let seenInFrame = used.contains(index)
            let clipped = !GeometryDistance.usableFrame.contains(last.box)
            let repeatedSmallBox = track.remembersSmallBox && track.reappearances >= 2
                && time - track.firstSeen >= stationarySeconds
            var currentReason: DistanceEvidence.RedReason = .belowThreshold
            var candidateReason: DistanceEvidence.RedReason
            var current = 0
            var candidate = 0
            if time - track.lastMovement >= stationarySeconds {
                currentReason = .stationary
                candidateReason = .stationary
                tracks[index].lastUnclipped = nil
            } else {
                current = proximityLevel(track.samples, at: time, redReason: &currentReason,
                                         recordEvidence: compareGeometry, viewUnstable: viewUnstable)
                candidate = clipped ? track.geometry.edgeLevel(at: time) : track.geometry.level
                if viewUnstable { candidateReason = .viewUnstable }
                else if clipped { candidateReason = candidate > 1 ? .edgeHold : .frameEdge }
                else { candidateReason = track.geometry.redReason }
                if clipped, let previous = track.lastUnclipped, time - previous.time <= 0.6 {
                    if previous.level > current { current = previous.level; currentReason = .edgeHold }
                } else if seenInFrame && !clipped && !viewUnstable {
                    tracks[index].lastUnclipped = (time, current)
                }
                // A remembered background box can suppress green for either rule independently.
                if repeatedSmallBox {
                    if current == 1 { current = 0; currentReason = .repeatedSmallBox }
                    if candidate == 1 { candidate = 0; candidateReason = .repeatedSmallBox }
                }
                levels.include(current, at: last.box.midX)
                if compareGeometry { geometryLevels.include(candidate, at: last.box.midX) }
            }
            if compareGeometry {
                evidence.append(DistanceEvidence(box: last.box, state: .init(current: currentReason, candidate: candidateReason,
                                                                              currentLevel: current, candidateLevel: candidate,
                                                                              seenInFrame: seenInFrame, clipped: clipped)))
            }
        }
        return (levels, compareGeometry ? geometryLevels : nil, evidence)
    }

    private func proximityLevel(_ history: [Sample], at time: TimeInterval, redReason: inout DistanceEvidence.RedReason,
                                recordEvidence: Bool, viewUnstable: Bool) -> Int {
        let recent = history.suffix(3).filter { time - $0.time <= 1 }
        let sizes = recent.map { Self.apparentSize($0.box) }.sorted(by: >)
        guard sizes.count >= 2 else {
            // A clear close-range size on entry may be the only near frame of a quick pass.
            if history.count == 1, !viewUnstable, (sizes.first ?? 0) >= 0.50 {
                redReason = .strongFirstFrame
                return 3
            }
            redReason = .needsMoreFrames
            return 1
        }
        // The second-largest size needs support from two frames and tolerates one outlier.
        let size = sizes[1]
        if size >= Self.redSizeThreshold { redReason = .confirmed; return 3 }
        if recordEvidence && recent.filter({ $0.box.height >= Self.redSizeThreshold }).count >= 2 {
            redReason = .widthLimited
        }
        if size >= 0.32 { return 2 }
        guard let box = recent.last?.box, Self.apparentSize(box) >= 0.25 else { return 1 }

        // A box growing as it comes into frame is weak evidence of approach.
        let earlierSizes = history.dropLast(2).prefix(3)
            .filter { GeometryDistance.usableFrame.contains($0.box) }
            .map { Self.apparentSize($0.box) }.sorted()
        guard !earlierSizes.isEmpty else { return 1 }
        let middle = earlierSizes.count / 2
        let baseline = (earlierSizes[middle] + earlierSizes[(earlierSizes.count - 1) / 2]) / 2
        let priority = focusZone?.contains(CGPoint(x: box.midX, y: box.midY)) ?? false
        let growth = 1 + (priority ? 0.10 : 0.18) / sensitivity
        if recent.suffix(2).allSatisfy({
            let size = Self.apparentSize($0.box)
            return size > baseline * growth && size - baseline > 0.025
        }) { return 2 }
        return 1
    }

    private static func apparentSize(_ box: CGRect) -> CGFloat {
        // Limit the influence of tall, narrow boxes.
        min(box.height, box.width * 3)
    }

    private func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }
}

struct GeometryDistance {
    static let usableFrame = CGRect(x: 0.01, y: 0.01, width: 0.98, height: 0.98)
    private var history: [CGRect] = []
    private var lastInside: TimeInterval?
    private(set) var level = 1
    var redReason: DistanceEvidence.RedReason {
        if level == 3 { return .confirmed }
        return history.count < 2 ? .needsMoreFrames : .belowThreshold
    }

    func edgeLevel(at time: TimeInterval) -> Int {
        hasRecentInside(at: time) ? level : 1
    }

    private func hasRecentInside(at time: TimeInterval) -> Bool {
        lastInside.map { time - $0 <= 0.6 } ?? false
    }

    mutating func update(_ box: CGRect, at time: TimeInterval, growth: Double) {
        let recentInside = hasRecentInside(at: time)
        guard Self.usableFrame.contains(box) else {
            if !recentInside || level == 1 { self = GeometryDistance() }
            return
        }
        if !recentInside { self = GeometryDistance() }
        lastInside = time
        history.append(box)
        if history.count > 5 { history.removeFirst() }
        guard history.count >= 2 else { return }

        let heights = history.suffix(3).map(\.height).sorted(by: >)
        let confirmedHeight = heights[1]
        let near = confirmedHeight >= (level >= 2 ? 0.25 : 0.32)
        let veryNear = confirmedHeight >= (level == 3 ? 0.40 : 0.45)
        level = veryNear ? 3 : (near || showsApproach(growth: growth) ? 2 : 1)
    }

    private func showsApproach(growth: Double) -> Bool {
        guard history.count >= 3, let latest = history.last, latest.height >= 0.25 else { return false }
        let earlier = history.dropLast(2).sorted { $0.height < $1.height }
        let reference = earlier[earlier.count / 2]
        guard reference.height > 0, reference.width > 0 else { return false }

        return history.suffix(2).allSatisfy {
            let heightScale = $0.height / reference.height
            let widthScale = $0.width / reference.width
            return heightScale >= 1 + growth && widthScale >= 1.10
                && abs(log(heightScale / widthScale)) <= 0.18
        }
    }
}
