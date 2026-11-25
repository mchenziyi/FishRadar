import CoreGraphics
import Foundation

// For this idealized 16:9 camera, fx / imageWidth = 0.60 and fy / imageHeight ≈ 1.07.
func project(x: CGFloat, z: CGFloat, width: CGFloat = 0.27, height: CGFloat = 0.60,
             zoom: CGFloat = 1) -> CGRect {
    let w = 0.60 * zoom * width / z
    let h = (0.60 * 16 / 9) * zoom * height / z
    let u = 0.5 + 0.60 * zoom * x / z
    return CGRect(x: u - w / 2, y: 0.5 - h / 2, width: w, height: h)
        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
}

struct Scenario {
    let name: String
    let frames: [CGRect]
    let expected: [Int]
    var unstableViewFrom: Int? = nil
}

let far = project(x: 0.8, z: 3)
let wideNear = project(x: 0.6, z: 1.60)
let sideNear = project(x: 0.6, z: 1.60, width: 0.16)
let scenarios = [
    Scenario(name: "远处横穿", frames: [0.6, 0.8, 1.0].map { project(x: $0, z: 3.5) }, expected: [1, 1, 1]),
    Scenario(name: "远处出现在画面边缘", frames: [1.7, 1.8, 1.9].map { project(x: $0, z: 3) }, expected: [1, 1, 1]),
    Scenario(name: "近处横穿", frames: [0.4, 0.5, 0.6].map { project(x: $0, z: 1.6) }, expected: [1, 2, 2]),
    Scenario(name: "很近处直接入画", frames: [0.4, 0.5, 0.6].map { project(x: $0, z: 1.2) }, expected: [1, 3, 3]),
    Scenario(name: "同一人走近", frames: [3.6, 2.45, 2.35, 1.57].map { project(x: 0.6, z: $0) }, expected: [1, 1, 2, 2]),
    Scenario(name: "远处框变高但未变宽", frames: [far, project(x: 0.8, z: 3, height: 0.75), project(x: 0.8, z: 3, height: 0.78)], expected: [1, 1, 1]),
    Scenario(name: "近处转身", frames: [wideNear, wideNear, sideNear, sideNear], expected: [1, 2, 2, 2]),
    Scenario(name: "近距阈值抖动", frames: [1.80, 1.80, 2.06, 2.06, 1.80].map { project(x: 0.6, z: $0) }, expected: [1, 2, 2, 2, 2]),
    Scenario(name: "从近处退远", frames: [1.60, 1.60, 2.90, 2.90].map { project(x: 0.6, z: $0) }, expected: [1, 2, 2, 1]),
    Scenario(name: "单帧大框", frames: [far, project(x: 0.45, z: 1.2), far], expected: [1, 1, 1]),
    Scenario(name: "已知视角变化", frames: [far, far, project(x: 0.8, z: 3, zoom: 2), project(x: 0.8, z: 3, zoom: 2)], expected: [1, 1, 1, 1], unstableViewFrom: 2),
]
for scenario in scenarios {
    var tracker = ApproachTracker()
    let comparisons = scenario.frames.enumerated().map { index, box in
        let viewUnstable = scenario.unstableViewFrom.map { index >= $0 } ?? false
        return tracker.update([box], at: Double(index) * 0.4, compareGeometry: true, viewUnstable: viewUnstable)
    }
    let preview = comparisons.map { max($0.current.left, $0.current.right) }
    let prototype = comparisons.map {
        guard let geometry = $0.geometry else { preconditionFailure("Missing geometry result") }
        return max(geometry.left, geometry.right)
    }
    print("\(scenario.name) | 现有 \(preview) | 几何 \(prototype)")
    precondition(prototype == scenario.expected, "Unexpected proximity levels for \(scenario.name)")
}

let personA = project(x: 0.6, z: 2)
let personB = project(x: 0.45, z: 1.5, width: 0.2025, height: 0.45)
func sameProjection(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.midX - b.midX) < 1e-9 && abs(a.midY - b.midY) < 1e-9
        && abs(a.height - b.height) < 1e-9 && abs(a.width - b.width) < 1e-9
}
precondition(sameProjection(personA, personB))
print("尺度歧义验证通过：两种不同距离和人体尺寸可以投影为同一个框。")
precondition(sameProjection(project(x: 0.6, z: 3, zoom: 1.5), project(x: 0.6, z: 2)))
print("变焦歧义验证通过：相同人物在远处放大和实际走近可以投影为同一个框。")
