import AppKit
import AVFoundation

final class DistanceGuideLayer: CALayer {
    var guides: DistanceGuideFrame? {
        didSet {
            isHidden = guides == nil
            if guides != oldValue { setNeedsDisplay() }
        }
    }

    override func draw(in ctx: CGContext) { guides?.draw(in: ctx, area: bounds) }

    func align(to preview: AVCaptureVideoPreviewLayer, scale: CGFloat) {
        let rect = preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let target = rect.isNull || rect.isInfinite ? .zero : rect
        guard frame != target || contentsScale != scale else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentsScale = scale
        frame = target
        CATransaction.commit()
    }
}

// Zones are stored in unmirrored Vision coordinates (origin at bottom left).
final class RegionView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    private let overlay = CAShapeLayer()
    private let distanceGuides = DistanceGuideLayer()
    var zone: CGRect? { didSet { updateOverlay() } }
    func showDistanceGuides(_ frame: DistanceGuideFrame?) {
        if frame != nil && distanceGuides.isHidden { layoutDistanceGuides() }
        distanceGuides.guides = frame
    }
    var onChange: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        preview.videoGravity = .resizeAspect
        layer?.addSublayer(preview)
        layer?.addSublayer(overlay)
        layer?.addSublayer(distanceGuides)
        distanceGuides.isHidden = true
        distanceGuides.needsDisplayOnBoundsChange = true
        overlay.fillColor = NSColor.systemOrange.withAlphaComponent(0.25).cgColor
        overlay.strokeColor = NSColor.systemOrange.cgColor
        overlay.lineWidth = 2
        NotificationCenter.default.addObserver(self, selector: #selector(sessionDidStart(_:)),
                                               name: AVCaptureSession.didStartRunningNotification, object: session)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout(); preview.frame = bounds; overlay.frame = bounds
        refreshPreview()
    }
    @objc private func sessionDidStart(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.refreshPreview() }
    }
    private func refreshPreview() {
        if let c = preview.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true
        }
        updateOverlay()
        if !distanceGuides.isHidden { layoutDistanceGuides() }
    }
    private func layoutDistanceGuides() {
        distanceGuides.align(to: preview, scale: window?.backingScaleFactor ?? 1)
    }
    private func updateOverlay() {
        overlay.path = displayRect().map { CGPath(rect: $0, transform: nil) }
    }
    private func videoRect() -> CGRect { preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1)) }
    private func displayRect() -> CGRect? {
        if let start, let current { return CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x-current.x), height: abs(start.y-current.y)) }
        guard let z = zone else { return nil }
        let v = videoRect()
        let shown = mirrorZone(z)
        return CGRect(x: v.minX + shown.minX * v.width, y: v.minY + shown.minY * v.height, width: shown.width * v.width, height: shown.height * v.height)
    }
    private func clipped(_ point: NSPoint) -> NSPoint {
        let v = videoRect()
        return NSPoint(x: max(v.minX, min(v.maxX, point.x)), y: max(v.minY, min(v.maxY, point.y)))
    }
    override func mouseDown(with event: NSEvent) { start = clipped(convert(event.locationInWindow, from: nil)); current = start; updateOverlay() }
    override func mouseDragged(with event: NSEvent) { current = clipped(convert(event.locationInWindow, from: nil)); updateOverlay() }
    override func mouseUp(with event: NSEvent) {
        current = clipped(convert(event.locationInWindow, from: nil))
        let rect = displayRect(), v = videoRect()
        if let rect, rect.width > 5, rect.height > 5, v.width > 0, v.height > 0 {
            zone = mirrorZone(CGRect(x: (rect.minX-v.minX)/v.width, y: (rect.minY-v.minY)/v.height, width: rect.width/v.width, height: rect.height/v.height))
            onChange?(zone)
        }
        start = nil; current = nil; updateOverlay()
    }
}
