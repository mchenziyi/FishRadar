import CoreGraphics

let area = CGRect(x: 10, y: 20, width: 400, height: 200)
let rawBox = CGRect(x: 0.125, y: 0.25, width: 0.25, height: 0.375)
let display = distanceGuideRect(rawBox, in: area)
precondition(display == CGRect(x: 260, y: 70, width: 100, height: 75))

let source = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
source.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
source.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
source.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
source.fill(CGRect(x: 200, y: 0, width: 200, height: 200))

let guide = DistanceGuideFrame(boxes: [.init(rect: rawBox, role: .tracked)],
                               current: RadarLevels(left: 0, right: 1),
                               geometry: RadarLevels(left: 0, right: 2), viewUnstable: false)
let annotated = guide.annotatedPhoto(source.makeImage()!)!
precondition(annotated.width == 400 && annotated.height == 200)
let readback = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                            CGBitmapInfo.byteOrder32Big.rawValue)!
readback.draw(annotated, in: CGRect(x: 0, y: 0, width: 400, height: 200))
let pixels = readback.data!.assumingMemoryBound(to: UInt8.self)
func color(at x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
    let offset = y * readback.bytesPerRow + x * 4
    return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
}
let left = color(at: 4, y: 100)
let right = color(at: 395, y: 100)
precondition(left.2 > 240 && left.0 < 20)
precondition(right.0 > 240 && right.2 < 20)
let outline = color(at: 250, y: 100)
precondition(outline.1 > 120, "The guide outline should be on the mirrored side of the saved photo")

let compactArea = CGRect(x: 0, y: 0, width: 180, height: 100)
let compact = CGContext(data: nil, width: 180, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                            CGBitmapInfo.byteOrder32Big.rawValue)!
compact.setFillColor(CGColor(gray: 1, alpha: 1))
compact.fill(compactArea)
guide.draw(in: compact, area: compactArea)
let compactPixels = compact.data!.assumingMemoryBound(to: UInt8.self)
let row = 50 * compact.bytesPerRow
precondition(compactPixels[row + 110 * 4 + 1] < 130, "A bright background needs the dark outline")
precondition(compactPixels[row + 112 * 4 + 1] > 225, "Compact mode keeps the colored person outline")
precondition(compactPixels[10 * compact.bytesPerRow + 10 * 4] == 255, "Compact area should have no header label")
print("Distance guides: photo mirroring, outlined strokes and compact display verified")
