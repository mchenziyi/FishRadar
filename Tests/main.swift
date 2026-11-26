import Foundation
import CoreGraphics
func box(_ x: CGFloat, _ height: CGFloat) -> CGRect { CGRect(x: x, y: 0.2, width: 0.1, height: height) }
var tracker = ApproachTracker()
assert(tracker.update([box(0.7, 0.2)], at: 10) == RadarLevels(left: 1, right: 0))
assert(tracker.update([box(0.7, 0.24)], at: 10.4) == RadarLevels(left: 1, right: 0))
assert(tracker.update([box(0.7, 0.26)], at: 10.8) == RadarLevels(left: 2, right: 0))
assert(tracker.update([box(0.7, 0.31)], at: 11.2) == RadarLevels(left: 2, right: 0))
assert(tracker.update([], at: 16) == RadarLevels())
var right = ApproachTracker()
_ = right.update([box(0.1, 0.2)], at: 10)
_ = right.update([box(0.1, 0.24)], at: 10.4)
assert(right.update([box(0.1, 0.26)], at: 10.8) == RadarLevels(left: 0, right: 2))
var passing = ApproachTracker()
_ = passing.update([box(0.1, 0.2)], at: 10)
_ = passing.update([box(0.2, 0.2)], at: 10.4)
assert(passing.update([box(0.3, 0.2)], at: 10.8) == RadarLevels(left: 0, right: 1))
func upperBody(_ x: CGFloat, _ height: CGFloat, _ width: CGFloat) -> CGRect {
    CGRect(x: x, y: 0.2, width: width, height: height)
}
do {
    // A very close person can appear cropped, then get smaller while walking away.
    let first = CGRect(x: 0.69, y: 0, width: 0.22, height: 0.78)
    let frames = [
        first, upperBody(0.73, 0.37, 0.15), upperBody(0.79, 0.35, 0.14),
        upperBody(0.83, 0.24, 0.10), upperBody(0.86, 0.22, 0.09),
    ]
    for mirrored in [false, true] {
        var retreat = ApproachTracker()
        let levels = frames.enumerated().map { index, frame in
            let result = retreat.update([mirrored ? mirrorZone(frame) : frame], at: Double(index) * 0.4,
                                        compareGeometry: true)
            if index == 0 {
                assert(result.evidence.first?.logValues["current_red_reason"] as? String == "strong_first_frame")
            }
            return mirrored ? result.current.right : result.current.left
        }
        assert(levels == [3, 2, 2, 2, 1], "A clearly near first sight should warn red before fading to yellow and green")
    }

    var unstable = ApproachTracker()
    assert(unstable.update([first], at: 0, viewUnstable: true).left == 1)
    var narrow = ApproachTracker()
    assert(narrow.update([upperBody(0.72, 0.78, 0.14)], at: 0).left == 1)
}
var closePass = ApproachTracker()
assert(closePass.update([upperBody(0.68, 0.48, 0.17)], at: 0).left == 1)
assert(closePass.update([upperBody(0.76, 0.48, 0.17)], at: 0.4).left == 3, "A near person should warn even when moving sideways")
assert(closePass.update([], at: 0.8).left == 3, "One missed frame should not rearm the warning")
assert(closePass.update([], at: 1.1) == RadarLevels())

var alreadyNear = ApproachTracker()
let nearBox = upperBody(0.1, 0.36, 0.13)
assert(alreadyNear.update([nearBox], at: 0).right == 1)
assert(alreadyNear.update([nearBox], at: 0.4).right == 2)
for time in stride(from: 0.8, through: 5.0, by: 0.4) { _ = alreadyNear.update([nearBox], at: time) }
assert(alreadyNear.update([nearBox], at: 5).right == 0, "A fixed seat should still become quiet")

var farGrowth = ApproachTracker()
_ = farGrowth.update([box(0.7, 0.16)], at: 0)
_ = farGrowth.update([box(0.7, 0.20)], at: 0.4)
assert(farGrowth.update([box(0.7, 0.215)], at: 0.8).left == 1, "Size growth at a distance should stay green")

var boxSpike = ApproachTracker()
let farBox = box(0.7, 0.2)
_ = boxSpike.update([farBox], at: 0)
assert(boxSpike.update([upperBody(0.7, 0.52, 0.17)], at: 0.4).left == 1)
assert(boxSpike.update([farBox], at: 0.8).left == 1)

var edgeEntry = ApproachTracker()
_ = edgeEntry.update([upperBody(0.9, 0.18, 0.10)], at: 0)
_ = edgeEntry.update([upperBody(0.8, 0.29, 0.11)], at: 0.4)
assert(edgeEntry.update([upperBody(0.75, 0.29, 0.11)], at: 0.8).left == 1, "An initial clipped box should not establish approach")

do {
    // Box sizes from two close passes that previously stopped at yellow.
    let passes = [
        [upperBody(0.8536, 0.5219, 0.1464), upperBody(0.7641, 0.5088, 0.1998)],
        [upperBody(0.685, 0.4879, 0.1419), upperBody(0.777, 0.4898, 0.1628)],
    ]
    for frames in passes {
        var earlierRed = ApproachTracker()
        assert(earlierRed.update([frames[0]], at: 0).left == 1, "One frame alone should not confirm red")
        assert(earlierRed.update([frames[1]], at: 0.2).left == 3, "Two close observations should confirm red earlier")
    }

    for (person, expected) in [
        (upperBody(0.73, 0.30, 0.13), 1),
        (upperBody(0.73, 0.39, 0.16), 2),
        (upperBody(0.73, 0.52, 0.10), 1),
    ] {
        var unchanged = ApproachTracker()
        _ = unchanged.update([person], at: 0)
        assert(unchanged.update([person.offsetBy(dx: 0.02, dy: 0)], at: 0.2).left == expected)
    }
}
print("ApproachTracker tests passed")
var seated = ApproachTracker()
for i in 0..<5 { assert(seated.update([box(0.1, 0.2)], at: Double(i)) == RadarLevels(left: 0, right: 1)) }
assert(seated.update([box(0.1, 0.2)], at: 5) == RadarLevels())
assert(seated.update([box(0.16, 0.2)], at: 6) == RadarLevels(left: 0, right: 1))
var custom = ApproachTracker()
custom.stationarySeconds = 2
assert(custom.update([box(0.1, 0.2)], at: 0) == RadarLevels(left: 0, right: 1))
_ = custom.update([box(0.1, 0.2)], at: 1)
assert(custom.update([box(0.1, 0.2)], at: 2) == RadarLevels())

let seat = CGRect(x: 0.0, y: 0.0, width: 0.4, height: 1)
assert(!includesDetection(box(0.1, 0.2), effective: nil, ignore: seat))
assert(includesDetection(box(0.5, 0.2), effective: nil, ignore: seat))
assert(!includesDetection(box(0.5, 0.2), effective: seat, ignore: nil))
assert(includesDetection(box(0.1, 0.2), effective: seat, ignore: nil))

let displayed = CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.3)
let raw = mirrorZone(displayed)
assert(abs(raw.minX - 0.65) < 0.00001)
assert(abs(mirrorZone(raw).minX - displayed.minX) < 0.00001)
assert(!includesDetection(CGRect(x: 0.7, y: 0.25, width: 0.1, height: 0.1), effective: nil, ignore: raw))
// Status-only changes must never trigger automatic photographs.
assert(!shouldCaptureAutomaticPhoto(previous: RadarLevels(), current: RadarLevels()))
assert(!shouldCaptureAutomaticPhoto(previous: nil, current: RadarLevels()))
assert(shouldCaptureAutomaticPhoto(previous: RadarLevels(), current: RadarLevels(left: 1, right: 0)))
assert(shouldCaptureAutomaticPhoto(previous: RadarLevels(left: 1, right: 0), current: RadarLevels(left: 2, right: 0)))
assert(!shouldCaptureAutomaticPhoto(previous: RadarLevels(left: 1, right: 0), current: RadarLevels()))

assert(!shouldSwitchToWorkApp(previous: RadarLevels(), current: RadarLevels(left: 1, right: 0)))
assert(shouldSwitchToWorkApp(previous: RadarLevels(left: 1, right: 0), current: RadarLevels(left: 2, right: 0)))
assert(shouldSwitchToWorkApp(previous: RadarLevels(), current: RadarLevels(left: 0, right: 3)))
assert(shouldSwitchToWorkApp(previous: nil, current: RadarLevels(left: 2, right: 0)))
assert(!shouldSwitchToWorkApp(previous: RadarLevels(left: 2, right: 0), current: RadarLevels(left: 3, right: 0)))
assert(!shouldSwitchToWorkApp(previous: RadarLevels(left: 2, right: 0), current: RadarLevels(left: 0, right: 2)))
assert(!shouldSwitchToWorkApp(previous: RadarLevels(left: 2, right: 0), current: nil))
assert(shouldSwitchToWorkApp(previous: RadarLevels(), current: RadarLevels(left: 0, right: 2)))

assert(detectionInterval(lastAlert: nil, now: 10) == 0.4)
assert(detectionInterval(lastAlert: 10, now: 11) == 0.2)
assert(detectionInterval(lastAlert: 10, now: 12) == 0.4)

var comparisonTracker = ApproachTracker()
let slenderNear = upperBody(0.70, 0.40, 0.095)
let farOnRight = upperBody(0.10, 0.18, 0.08)
let comparisonFirst = comparisonTracker.update([slenderNear, farOnRight], at: 0, compareGeometry: true)
assert(comparisonFirst.geometry == RadarLevels(left: 1, right: 1))
let comparisonNext = comparisonTracker.update([farOnRight, slenderNear], at: 0.4, compareGeometry: true)
assert(comparisonNext.current == RadarLevels(left: 1, right: 1))
assert(comparisonNext.geometry == RadarLevels(left: 2, right: 1))
assert(!shouldSwitchToWorkApp(previous: comparisonFirst.current, current: comparisonNext.current))
let unstable = comparisonTracker.update([slenderNear], at: 0.8, compareGeometry: true, viewUnstable: true)
assert(unstable.geometry == RadarLevels(left: 1, right: 1))
assert(comparisonTracker.update([slenderNear], at: 1.2, compareGeometry: true).geometry?.left == 1)
assert(comparisonTracker.update([slenderNear], at: 1.6, compareGeometry: true).geometry?.left == 2)
assert(comparisonTracker.update([slenderNear], at: 2, compareGeometry: false).geometry == nil)
comparisonTracker.resetGeometry()
assert(comparisonTracker.update([slenderNear], at: 2.4, compareGeometry: true).geometry?.left == 1)
assert(comparisonTracker.update([slenderNear], at: 2.8, compareGeometry: true).geometry?.left == 2)
assert(comparisonTracker.update([slenderNear], at: 3.6, compareGeometry: true).geometry?.left == 1)
assert(comparisonTracker.update([slenderNear], at: 5, compareGeometry: true).geometry?.left == 1)

do {
    var intermittent = ApproachTracker()
    let chair = upperBody(0.02, 0.15, 0.055)
    assert(intermittent.update([chair], at: 0).right == 1)
    assert(intermittent.update([], at: 2).right == 0)
    assert(intermittent.update([chair.offsetBy(dx: 0.003, dy: 0)], at: 2.4).right == 1)
    assert(intermittent.update([], at: 5).right == 0)
    assert(intermittent.update([chair], at: 5.4).right == 0, "A fixed small box should stop rearming green after repeated gaps")
    assert(intermittent.update([upperBody(0.02, 0.42, 0.15)], at: 5.8).right == 1, "Growth at the same location should restore detection")
    assert(intermittent.update([upperBody(0.02, 0.42, 0.15)], at: 6.2).right == 3)

    var remembered = ApproachTracker()
    _ = remembered.update([chair], at: 0)
    _ = remembered.update([chair], at: 3)
    let suppressed = remembered.update([chair], at: 6, compareGeometry: true)
    assert(suppressed.current.right == 0 && suppressed.geometry?.right == 0)
    assert(suppressed.evidence.first?.state.current == .repeatedSmallBox)
    var expiredMemory = remembered
    assert(expiredMemory.update([chair], at: 68).right == 1, "Memory should expire after 60 seconds without a match")
    assert(remembered.update([chair.offsetBy(dx: 0.03, dy: 0)], at: 6.4).right == 1)
}

do {
    // Observed at the left edge after mirroring. The box is tall but unusually narrow.
    let fixed = CGRect(x: 0.9365, y: 0.283, width: 0.061, height: 0.244)
    let jitter = CGRect(x: 0.935, y: 0.281, width: 0.062, height: 0.249)
    var narrowEdge = ApproachTracker()
    assert(narrowEdge.update([fixed], at: 0).left == 1)
    assert(narrowEdge.update([], at: 1).left == 0)
    assert(narrowEdge.update([jitter], at: 2).left == 1)
    assert(narrowEdge.update([], at: 4).left == 0)
    let suppressed = narrowEdge.update([fixed], at: 6, compareGeometry: true)
    assert(suppressed.current.left == 0 && suppressed.geometry?.left == 0, "A recurring fixed narrow box should stop rearming green")
    assert(suppressed.evidence.first?.state.current == .repeatedSmallBox)

    var passingEdge = narrowEdge
    assert(passingEdge.update([fixed.offsetBy(dx: -0.03, dy: 0)], at: 6.2).left == 1)
    let closePerson = upperBody(0.81, 0.49, 0.17)
    assert(narrowEdge.update([closePerson], at: 6.2, compareGeometry: true).current.left == 1)
    let close = narrowEdge.update([closePerson], at: 6.4, compareGeometry: true)
    assert(close.current.left == 3 && close.geometry?.left == 3)
}

do {
    var narrowNear = ApproachTracker()
    let narrow = upperBody(0.78, 0.49, 0.06)
    for time in [0.0, 3.0, 6.0] {
        _ = narrowNear.update([narrow], at: time, compareGeometry: true)
    }
    let confirmed = narrowNear.update([narrow], at: 6.2, compareGeometry: true)
    assert(confirmed.current.left == 0)
    assert(confirmed.geometry?.left == 3, "Green suppression should preserve independently confirmed red")
}

do {
    for (height, grade) in [(0.36, 2), (0.49, 3)] {
        var clippedPass = ApproachTracker()
        let inside = upperBody(0.03, height, 0.16)
        let clipped = upperBody(0, 0.24, 0.07)
        _ = clippedPass.update([inside], at: 0, compareGeometry: true)
        let confirmed = clippedPass.update([inside], at: 0.25, compareGeometry: true)
        assert(confirmed.current.right == grade && confirmed.geometry?.right == grade)
        for time in [0.5, 0.75] {
            let held = clippedPass.update([clipped], at: time, compareGeometry: true)
            assert(held.current.right == grade && held.geometry?.right == grade, "Clipping should briefly retain the previously confirmed grade")
            assert(held.evidence.first?.state.candidate == .edgeHold)
        }
        let expired = clippedPass.update([clipped], at: 1, compareGeometry: true)
        assert(expired.current.right == 1 && expired.geometry?.right == 1, "Clipped frames should not extend the hold")
    }
    var reentry = ApproachTracker()
    let inside = upperBody(0.03, 0.48, 0.17)
    let clipped = upperBody(0, 0.24, 0.07)
    _ = reentry.update([inside], at: 0, compareGeometry: true)
    _ = reentry.update([inside], at: 0.2, compareGeometry: true)
    _ = reentry.update([clipped], at: 0.4, compareGeometry: true)
    assert(reentry.update([inside], at: 0.6, compareGeometry: true).geometry?.right == 3)
    let reframed = reentry.update([clipped], at: 0.8, compareGeometry: true, viewUnstable: true)
    assert(reframed.geometry?.right == 1 && reframed.evidence.first?.state.candidate == .viewUnstable)

    var missing = ApproachTracker()
    _ = missing.update([inside], at: 0, compareGeometry: true)
    _ = missing.update([inside], at: 0.2, compareGeometry: true)
    _ = missing.update([clipped], at: 0.6, compareGeometry: true)
    assert(missing.update([], at: 0.85, compareGeometry: true).geometry?.right == 1)
}

do {
    var diagnostic = ApproachTracker()
    let narrow = upperBody(0.1, 0.50, 0.085)
    let first = diagnostic.update([narrow], at: 0, compareGeometry: true)
    assert(first.evidence.first?.state.current == .needsMoreFrames)
    let second = diagnostic.update([narrow], at: 0.2, compareGeometry: true)
    assert(second.current.right == 1 && second.geometry?.right == 3)
    let fields = second.evidence.first!.logValues
    assert(fields["height"] as? Double == 0.50 && fields["width"] as? Double == 0.085)
    assert(fields["current_red_reason"] as? String == "width_limited")
    assert(fields["candidate_red_reason"] as? String == "confirmed")
    assert(fields["clipped"] as? Bool == false)
    assert(JSONSerialization.isValidJSONObject(["red_evidence": [fields]]))
    assert(diagnostic.update([narrow], at: 0.4, compareGeometry: false).evidence.isEmpty)
}
