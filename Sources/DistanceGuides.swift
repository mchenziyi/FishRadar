import CoreGraphics
import CoreText
import Foundation

func distanceGuideRect(_ raw: CGRect, in area: CGRect) -> CGRect {
    let shown = mirrorZone(raw)
    return CGRect(x: area.minX + shown.minX * area.width, y: area.minY + shown.minY * area.height,
                  width: shown.width * area.width, height: shown.height * area.height)
}

struct DistanceGuideFrame: Equatable {
    struct Box: Equatable {
        enum Role { case tracked, userHead, userBody, ignored }
        let rect: CGRect
        let role: Role
    }

    let boxes: [Box]
    let current: RadarLevels
    let geometry: RadarLevels?
    let viewUnstable: Bool

    static func userBoxes(in person: CGRect, faces: [CGRect]) -> [Box] {
        let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let person = person.intersection(frame)
        guard !person.isEmpty else { return [] }
        let face = faces.filter {
            person.contains(CGPoint(x: $0.midX, y: $0.midY))
                && $0.midY > person.midY && $0.width >= person.width * 0.22
                && $0.height >= person.height * 0.18
        }.max { $0.width * $0.height < $1.width * $1.height }

        let head: CGRect
        if let face {
            let bottom = face.minY - face.height * 0.08
            let top = max(person.maxY, face.maxY + face.height * 0.18)
            head = CGRect(x: face.minX - face.width * 0.14, y: bottom,
                          width: face.width * 1.28, height: top - bottom).intersection(frame)
        } else {
            head = CGRect(x: person.midX - person.width * 0.23, y: person.minY + person.height * 0.54,
                          width: person.width * 0.46, height: person.height * 0.46)
        }
        let shoulder = min(person.maxY, head.minY + head.height * 0.04)
        let body = CGRect(x: person.minX, y: person.minY, width: person.width,
                          height: max(0, shoulder - person.minY))
        return [Box(rect: body, role: .userBody), Box(rect: head, role: .userHead)].filter { !$0.rect.isEmpty }
    }

    func draw(in context: CGContext, area: CGRect) {
        guard area.width > 0, area.height > 0 else { return }
        let compact = area.width < 280 || area.height < 160
        let scale = max(1, area.height / 354)
        let white = CGColor(gray: 1, alpha: 1)
        let muted = CGColor(gray: 0.90, alpha: 1)
        let tracked = CGColor(red: 0.12, green: 1, blue: 1, alpha: 1)
        let headColor = CGColor(red: 0.16, green: 0.64, blue: 1, alpha: 1)
        let bodyColor = CGColor(red: 1, green: 0.30, blue: 0.30, alpha: 1)

        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: area)

        func stroke(_ path: CGPath, color: CGColor, width: CGFloat, dashed: Bool = false) {
            context.setLineDash(phase: 0, lengths: dashed ? [5 * scale, 4 * scale] : [])
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.95))
            context.setLineWidth((width + 2) * scale)
            context.addPath(path)
            context.strokePath()
            context.setStrokeColor(color)
            context.setLineWidth(width * scale)
            context.addPath(path)
            context.strokePath()
        }
        let dividers = CGMutablePath()
        for fraction in [0.42, 0.58] {
            let x = area.minX + area.width * fraction
            dividers.move(to: CGPoint(x: x, y: area.minY))
            dividers.addLine(to: CGPoint(x: x, y: area.maxY))
        }
        stroke(dividers, color: white, width: 2, dashed: true)

        let font = compact ? nil : CTFontCreateWithName("PingFangSC-Regular" as CFString, 12 * scale, nil)
        func label(_ value: String, x: CGFloat, y: CGFloat, color: CGColor = white) {
            guard let font else { return }
            let text = NSAttributedString(string: value, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ])
            let line = CTLineCreateWithAttributedString(text)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + 8 * scale
            let originX = max(area.minX, min(x, area.maxX - width))
            context.setFillColor(CGColor(gray: 0, alpha: 0.78))
            context.fill(CGRect(x: originX, y: y, width: width, height: 18 * scale))
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: originX + 4 * scale, y: y + 4 * scale)
            CTLineDraw(line, context)
        }

        for box in boxes {
            let isTracked = box.role == .tracked
            if compact && !isTracked { continue }
            let rect = distanceGuideRect(box.rect, in: area).intersection(area)
            guard !rect.isEmpty else { continue }
            let height = Int((box.rect.height * 100).rounded())
            let color: CGColor
            let name: String
            switch box.role {
            case .tracked: (color, name) = (tracked, "\(height)%")
            case .userHead: (color, name) = (headColor, "自己 · 头部")
            case .userBody: (color, name) = (bodyColor, "自己 · 上半身")
            case .ignored: (color, name) = (muted, "区域排除 \(height)%")
            }
            let ignored = box.role == .ignored
            stroke(CGPath(rect: rect, transform: nil), color: color, width: ignored ? 1.5 : 2.5, dashed: ignored)
            label(name, x: rect.minX, y: max(area.minY, rect.maxY - 18 * scale), color: color)
        }
        if compact { return }
        let rulerX = area.minX + 8 * scale
        let rulerBase = area.minY + 24 * scale
        let redReference = ApproachTracker.redSizeThreshold
        let ruler = CGMutablePath()
        ruler.move(to: CGPoint(x: rulerX, y: rulerBase))
        ruler.addLine(to: CGPoint(x: rulerX, y: rulerBase + redReference * area.height))
        for fraction in [0.0, 0.32, redReference] {
            let y = rulerBase + area.height * fraction
            ruler.move(to: CGPoint(x: rulerX, y: y))
            ruler.addLine(to: CGPoint(x: rulerX + 5 * scale, y: y))
        }
        stroke(ruler, color: white, width: 1.5)
        label("框高参考", x: rulerX, y: area.minY + 3 * scale)
        label("32%", x: rulerX + 7 * scale, y: rulerBase + 0.32 * area.height - 9 * scale)
        label("\(Int((redReference * 100).rounded()))%", x: rulerX + 7 * scale, y: rulerBase + redReference * area.height - 9 * scale)

        let names = ["白", "绿", "黄", "红"]
        func summary(_ levels: RadarLevels) -> String { "左\(names[levels.left]) 右\(names[levels.right])" }
        let candidate = viewUnstable ? "取景不稳" : geometry.map(summary) ?? "未采样"
        label("现用 \(summary(current))  ｜  候选 \(candidate)", x: area.minX + 5 * scale, y: area.maxY - 23 * scale)
    }

    func annotatedPhoto(_ image: CGImage) -> CGImage? {
        let area = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.saveGState()
        context.translateBy(x: area.width, y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(image, in: area)
        context.restoreGState()
        draw(in: context, area: area)
        return context.makeImage()
    }
}
