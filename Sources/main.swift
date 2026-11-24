import AppKit
import AVFoundation
import Vision
import CoreImage
import ImageIO
import ServiceManagement
import Darwin

final class DragPreview: NSView {
    var onDragEnd: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event); onDragEnd?() }
}

final class DraggableIndicator: NSImageView {
    var onDragEnd: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event); onDragEnd?() }
}

// All camera frames and inference stay in memory on this device.
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "FishRadar.camera")
    private var lastFrame = Date.distantPast
    private var receivedFrameCount: UInt64 = 0
    private var inferenceFrameCount: UInt64 = 0
    private var lastFrameSample: (time: TimeInterval, received: UInt64, inferred: UInt64)?
    private var lastAlert: TimeInterval?
    private var running = false
    private var captureDevice: AVCaptureDevice?
    private var cameraUseObservation: NSKeyValueObservation?
    private var cameraFrameRateObservation: NSKeyValueObservation?
    private var frameRateAttempts: [TimeInterval] = []
    private var originalFrameRate: (format: AVCaptureDevice.Format, min: CMTime, max: CMTime)?
    private var approachTracker = ApproachTracker()
    private var effectiveZone: CGRect?
    private var ignoreZone: CGRect?
    private var photoRequests: [(Result<Data, Error>) -> Void] = []
    private let imageContext = CIContext(options: nil)
    private var autoPhotoGeneration: Int?
    private var previousPhotoLevels: RadarLevels?
    var onAutomaticPhoto: ((Result<Data, Error>, Int, String, [[String: Any]]) -> Void)?
    var onStatus: ((String, RadarLevels?, String?) -> Void)?
    var onStarted: (() -> Void)?

    func updateConfiguration(effective: CGRect?, ignore: CGRect?, focus: CGRect?, sensitivity: Double) {
        queue.async {
            self.effectiveZone = effective
            self.ignoreZone = ignore
            self.approachTracker.focusZone = focus
            self.approachTracker.sensitivity = sensitivity
        }
    }

    func setAutomaticPhotos(generation: Int?) {
        queue.async { self.autoPhotoGeneration = generation; self.previousPhotoLevels = nil }
    }

    func requestPhoto(_ completion: @escaping (Result<Data, Error>) -> Void) {
        queue.async {
            guard self.running else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "FishRadar", code: 2, userInfo: [NSLocalizedDescriptionKey: "摄像头未运行，无法拍照。"]))) }
                return
            }
            self.photoRequests.append(completion)
        }
    }

    func resetFrameSample() {
        queue.async { self.lastFrameSample = nil }
    }

    func frameMetrics(_ completion: @escaping ([String: Any]) -> Void) {
        queue.async {
            let now = ProcessInfo.processInfo.systemUptime
            var metrics: [String: Any] = ["camera_running": self.running, "camera_authorization": AVCaptureDevice.authorizationStatus(for: .video).rawValue]
            if let previous = self.lastFrameSample, now > previous.time {
                let elapsed = now - previous.time
                metrics["capture_fps"] = Double(self.receivedFrameCount - previous.received) / elapsed
                metrics["detection_fps"] = Double(self.inferenceFrameCount - previous.inferred) / elapsed
            }
            self.lastFrameSample = (now, self.receivedFrameCount, self.inferenceFrameCount)
            if let device = self.captureDevice, self.running {
                let duration = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
                if duration.isFinite && duration > 0 { metrics["camera_max_fps"] = 1 / duration }
                metrics["frame_limit_applied"] = self.originalFrameRate != nil && duration.isFinite && duration >= 1.0 / 15.0 - 0.001
                metrics["camera_shared"] = device.isInUseByAnotherApplication
            }
            DispatchQueue.main.async { completion(metrics) }
        }
    }

    func setStationarySeconds(_ seconds: TimeInterval) {
        queue.async { self.approachTracker.stationarySeconds = seconds }
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            report("等待摄像头授权", nil)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                if allowed { self?.configure() } else { self?.report("摄像头权限未开启", nil) }
            }
        default: report("摄像头权限未开启，请在系统设置中允许访问", nil)
        }
    }

    private func configure() {
        queue.async { [weak self] in
            guard let self = self, !self.running else { return }
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.report("摄像头不可用", nil); return
            }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.sessionPreset = .medium
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.queue)
            guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                self.session.commitConfiguration(); self.report("无法启动摄像头", nil); return
            }
            self.session.addInput(input)
            self.session.addOutput(output)
            self.session.commitConfiguration()
            self.session.startRunning()
            self.running = self.session.isRunning
            if self.running {
                self.captureDevice = device
                self.cameraUseObservation = device.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] device, _ in
                    self?.queue.async { [weak self] in self?.updateCameraFrameRate(device) }
                }
                self.cameraFrameRateObservation = device.observe(\.activeVideoMinFrameDuration, options: [.new]) { [weak self] device, _ in
                    self?.queue.async { [weak self] in self?.updateCameraFrameRate(device) }
                }
                self.updateCameraFrameRate(device)
                DispatchQueue.main.async { self.onStarted?() }
            }
            self.report(self.running ? "正在检测" : "摄像头不可用", nil)
        }
    }

    private func canChangeFrameRate(_ device: AVCaptureDevice) -> Bool {
        if #available(macOS 15.0, *), device.isAutoVideoFrameRateEnabled { return false }
        if #available(macOS 26.0, *), device.isVideoFrameDurationLocked || device.isFollowingExternalSyncDevice { return false }
        return device.isConnected
    }

    private func updateCameraFrameRate(_ device: AVCaptureDevice) {
        guard running, captureDevice === device else { return }
        if device.isInUseByAnotherApplication {
            restoreCameraFrameRate()
            frameRateAttempts.removeAll()
            return
        }
        if let saved = originalFrameRate, device.activeFormat !== saved.format { originalFrameRate = nil }
        guard canChangeFrameRate(device),
              device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && $0.maxFrameRate >= 15 }) else { return }
        let target = CMTime(value: 1, timescale: 15)
        let current = device.activeVideoMinFrameDuration
        if current.isValid && CMTimeCompare(current, target) >= 0 { return }
        let now = ProcessInfo.processInfo.systemUptime
        frameRateAttempts.removeAll { now - $0 > 60 }
        // Stop retrying if the system or another client repeatedly overrides the setting.
        guard frameRateAttempts.count < 3 else { return }
        frameRateAttempts.append(now)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            guard !device.isInUseByAnotherApplication, canChangeFrameRate(device),
                  device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && $0.maxFrameRate >= 15 }) else { return }
            // The session can reset the frame rate when it starts, so set it afterward.
            if originalFrameRate == nil {
                originalFrameRate = (device.activeFormat, device.activeVideoMinFrameDuration, device.activeVideoMaxFrameDuration)
            }
            device.activeVideoMinFrameDuration = target
        } catch {
            // Keep the device's existing frame rate if it cannot be configured.
        }
    }

    private func restoreCameraFrameRate() {
        guard let saved = originalFrameRate, let device = captureDevice else { return }
        originalFrameRate = nil
        guard canChangeFrameRate(device), device.activeFormat === saved.format,
              CMTimeCompare(device.activeVideoMinFrameDuration, CMTime(value: 1, timescale: 15)) == 0 else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            guard canChangeFrameRate(device), device.activeFormat === saved.format,
                  CMTimeCompare(device.activeVideoMinFrameDuration, CMTime(value: 1, timescale: 15)) == 0 else { return }
            device.activeVideoMinFrameDuration = saved.min
            device.activeVideoMaxFrameDuration = saved.max
        } catch {}
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.cameraUseObservation?.invalidate(); self.cameraUseObservation = nil
            self.cameraFrameRateObservation?.invalidate(); self.cameraFrameRateObservation = nil
            self.frameRateAttempts.removeAll()
            self.restoreCameraFrameRate()
            self.captureDevice = nil
            self.session.stopRunning(); self.running = false
            self.previousPhotoLevels = nil
            self.lastAlert = nil
            let requests = self.photoRequests; self.photoRequests.removeAll()
            DispatchQueue.main.async { for request in requests { request(.failure(NSError(domain: "FishRadar", code: 2, userInfo: [NSLocalizedDescriptionKey: "摄像头已暂停，未拍照。"]))) } }
            let seconds = self.approachTracker.stationarySeconds
            let sensitivity = self.approachTracker.sensitivity
            let focus = self.approachTracker.focusZone
            self.approachTracker = ApproachTracker()
            self.approachTracker.stationarySeconds = seconds
            self.approachTracker.sensitivity = sensitivity
            self.approachTracker.focusZone = focus
            self.report("已暂停", nil)
        }
    }

    private func report(_ status: String, _ levels: RadarLevels?, eventID: String? = nil) {
        DispatchQueue.main.async { self.onStatus?(status, levels, eventID) }
    }
    private func jpeg(_ buffer: CVPixelBuffer) -> Result<Data, Error> {
        let frame = CIImage(cvPixelBuffer: buffer)
        let data = imageContext.jpegRepresentation(of: frame, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
        return data.map { .success($0) } ?? .failure(NSError(domain: "FishRadar", code: 3, userInfo: [NSLocalizedDescriptionKey: "照片编码失败。 "]))
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        receivedFrameCount += 1
        let now = Date()
        guard now.timeIntervalSince(lastFrame) >= detectionInterval(lastAlert: lastAlert, now: now.timeIntervalSinceReferenceDate),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = Date()
        if !photoRequests.isEmpty {
            let requests = photoRequests; photoRequests.removeAll()
            let result = jpeg(buffer)
            DispatchQueue.main.async { for request in requests { request(result) } }
        }
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = true
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            inferenceFrameCount += 1
            let boxes = (request.results ?? []).filter { $0.confidence >= 0.45 }.map(\.boundingBox)
            // The largest prominent central person is only a heuristic for the user.
            let candidate = boxes.indices.filter { i in
                let b = boxes[i]
                return b.contains(CGPoint(x: 0.5, y: 0.5)) && b.height > 0.45
            }.max { boxes[$0].width * boxes[$0].height < boxes[$1].width * boxes[$1].height }
            let otherBoxes = boxes.enumerated().filter { item in
                guard item.offset != candidate else { return false }
                return includesDetection(item.element, effective: effectiveZone, ignore: ignoreZone)
            }.map(\.element)
            let approaching = approachTracker.update(otherBoxes, at: Date().timeIntervalSinceReferenceDate)
            if approaching.left > 0 || approaching.right > 0 { lastAlert = now.timeIntervalSinceReferenceDate }
            let status = candidate == nil ? "检测中 · 无法确认使用者" : "正在检测"
            if let generation = autoPhotoGeneration,
               shouldCaptureAutomaticPhoto(previous: previousPhotoLevels, current: approaching) {
                let eventID = UUID().uuidString
                let boxInfo: [[String: Any]] = boxes.enumerated().map { item in
                    let b = item.element
                    return ["x": Double(b.minX), "y": Double(b.minY), "width": Double(b.width), "height": Double(b.height),
                            "is_user_candidate": item.offset == candidate,
                            "included": item.offset != candidate && includesDetection(b, effective: effectiveZone, ignore: ignoreZone)]
                }
                let result = jpeg(buffer)
                report(status, approaching, eventID: eventID)
                DispatchQueue.main.async { self.onAutomaticPhoto?(result, generation, eventID, boxInfo) }
            } else { report(status, approaching) }
            if autoPhotoGeneration != nil { previousPhotoLevels = approaching }
        } catch {
            report("人员检测不可用", nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let camera = CameraController()
    var statusItem: NSStatusItem!
    var window: NSWindow!
    var indicatorWindow: NSWindow!
    var indicatorView: NSImageView!
    var statusMenuItem: NSMenuItem!
    var lifecycle = DetectionLifecycle()
    var cameraRequested = true
    var pauseItem: NSMenuItem!
    var regionWindow: NSWindow?
    var regionView: RegionView?
    var regionPicker: NSPopUpButton?
    var resourceItem: NSMenuItem?
    var resourceTimer: Timer?
    var resourceGeneration = 0
    var lastUsage: (Date, Double)?
    let hotKeys = HotKeys()
    let diagnostics = Diagnostics()
    var lastLoggedStatus: String?
    var lastLoggedLevels: RadarLevels?
    var currentStatus = "正在启动"
    var currentLevels: RadarLevels?
    var lastRenderedLevels: RadarLevels?
    var hasRenderedLevels = false
    var settingsController: SettingsWindowController?
    var savePhotos = false
    var photoGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        indicatorWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 38, height: 22), styleMask: [.borderless], backing: .buffered, defer: false)
        indicatorWindow.isOpaque = false
        indicatorWindow.backgroundColor = .clear
        indicatorWindow.hasShadow = false
        indicatorWindow.isMovableByWindowBackground = false
        indicatorWindow.level = .statusBar
        indicatorWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        indicatorView = DraggableIndicator(frame: NSRect(x: 0, y: 0, width: 38, height: 22))
        indicatorView.wantsLayer = true
        indicatorView.layer?.backgroundColor = NSColor.clear.cgColor
        indicatorWindow.contentView = indicatorView
        if let screen = NSScreen.screens.first {
            let frame = screen.frame
            indicatorWindow.setFrameOrigin(NSPoint(x: frame.midX - 19, y: frame.midY - 11))
        }
        restorePosition(indicatorWindow, key: "indicatorPosition")
        (indicatorView as? DraggableIndicator)?.onDragEnd = { [weak self] in
            guard let self = self else { return }; self.snapAndSave(self.indicatorWindow, key: "indicatorPosition")
        }
        indicatorWindow.orderFrontRegardless()
        setRadarIcon(nil)
        let menu = NSMenu()
        statusMenuItem = menu.addItem(withTitle: "正在启动摄像头…", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "显示或隐藏后视镜", action: #selector(showMirror), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        resourceItem = NSMenuItem(title: "资源监控：关闭", action: nil, keyEquivalent: "")
        pauseItem = menu.addItem(withTitle: "暂停检测", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 FishRadar", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 101.25), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "FishRadar · 后视镜"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        let initialWidth = UserDefaults.standard.object(forKey: "mirrorWidth") as? Double ?? 180
        window.setContentSize(NSSize(width: initialWidth, height: initialWidth * 9 / 16))
        window.alphaValue = UserDefaults.standard.object(forKey: "mirrorOpacity") as? Double ?? 1
        window.center()
        restorePosition(window, key: "mirrorPosition")
        window.delegate = self
        let preview = DragPreview(frame: window.contentView!.bounds)
        preview.onDragEnd = { [weak self] in
            guard let self = self else { return }; self.snapAndSave(self.window, key: "mirrorPosition")
        }
        preview.autoresizingMask = [.width, .height]
        preview.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: camera.session)
        layer.videoGravity = .resizeAspect
        layer.frame = preview.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        preview.layer?.addSublayer(layer)
        window.contentView = preview
        camera.onStatus = { [weak self] status, levels, eventID in self?.update(status, levels, eventID: eventID) }
        camera.onAutomaticPhoto = { [weak self] result, generation, eventID, boxes in
            self?.saveDiagnosticPhoto(result, generation: generation, eventID: eventID, reason: "箭头亮起或升级", boxes: boxes)
        }
        camera.onStarted = {
            guard let connection = layer.connection, connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(didLock), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(didUnlock), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cameraError), name: AVCaptureSession.runtimeErrorNotification, object: camera.session)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        hotKeys.onAction = { [weak self] action in
            switch action {
            case 1: self?.showMirror()
            case 2: self?.togglePause()
            case 3:
                guard let self = self else { return }
                if self.indicatorWindow.isVisible { self.indicatorWindow.orderOut(nil) } else { self.indicatorWindow.orderFrontRegardless() }
            default: break
            }
        }
        if !hotKeys.configure(savedHotKeys()) { statusMenuItem.title = "快捷键注册失败，请在设置中调整" }
        applyDetectionSettings()
        camera.setStationarySeconds(UserDefaults.standard.object(forKey: "stationarySeconds") as? Double ?? 5)
        camera.start()
        if CommandLine.arguments.contains("--resume-monitoring") { toggleResources() }
        if CommandLine.arguments.contains("--settings") { DispatchQueue.main.async { self.showSettings() } }
    }

    func update(_ status: String, _ levels: RadarLevels?, eventID: String? = nil) {
        statusMenuItem.title = status
        let previousLevels = currentLevels
        currentStatus = status; currentLevels = levels
        if UserDefaults.standard.bool(forKey: "automaticAppSwitch"), shouldSwitchToWorkApp(previous: previousLevels, current: levels) {
            switchToWorkApp()
        }
        if resourceTimer != nil && (status != lastLoggedStatus || levels != lastLoggedLevels) {
            let id = eventID ?? UUID().uuidString
            writeDiagnostic("detection", ["id": id, "status": status, "left": levels?.left ?? -1, "right": levels?.right ?? -1])
            lastLoggedStatus = status; lastLoggedLevels = levels
        }
        settingsController?.updateStatus(status, levels: levels)
        if !hasRenderedLevels || lastRenderedLevels != levels {
            setRadarIcon(levels)
            lastRenderedLevels = levels
            hasRenderedLevels = true
        }
    }

    func setRadarIcon(_ levels: RadarLevels?) {
        let image = NSImage(size: NSSize(width: 34, height: 18))
        image.lockFocus()
        let colors: [NSColor] = [.white, .systemGreen, .systemYellow, .systemRed]
        let font = NSFont.systemFont(ofSize: 16, weight: .bold)
        let left = levels.map { colors[$0.left] } ?? .secondaryLabelColor
        let right = levels.map { colors[$0.right] } ?? .secondaryLabelColor
        ("‹" as NSString).draw(at: NSPoint(x: 3, y: 0), withAttributes: [.font: font, .foregroundColor: left])
        ("›" as NSString).draw(at: NSPoint(x: 21, y: 0), withAttributes: [.font: font, .foregroundColor: right])
        image.unlockFocus()
        image.isTemplate = false
        statusItem.button?.title = ""
        statusItem.button?.image = image
        indicatorView.image = image
        statusItem.button?.toolTip = levels == nil ? "FishRadar 不可用或已暂停" : "FishRadar 正在检测"
    }

    @objc func showMirror() {
        if window.isVisible { window.orderOut(nil) } else { window.orderFrontRegardless() }
    }
    @objc func setStationaryTime() {
        let alert = NSAlert()
        alert.messageText = "静止忽略时间"
        alert.informativeText = "持续静止多久后忽略该人员？请输入 1 到 300 秒。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: String(Int(UserDefaults.standard.object(forKey: "stationarySeconds") as? Double ?? 5)))
        field.frame = NSRect(x: 0, y: 0, width: 150, height: 24)
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            if let seconds = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), (1...300).contains(seconds) {
                UserDefaults.standard.set(seconds, forKey: "stationarySeconds")
                camera.setStationarySeconds(Double(seconds))
                return
            }
            alert.informativeText = "请输入 1 到 300 之间的整数（秒）。"
        }
    }
    private func reconcileDetection() {
        let shouldRun = lifecycle.shouldRun
        guard shouldRun != cameraRequested else { return }
        cameraRequested = shouldRun
        if shouldRun { camera.start() } else { camera.stop() }
    }
    @objc func togglePause() {
        lifecycle.manuallyPaused.toggle()
        pauseItem.title = lifecycle.manuallyPaused ? "恢复检测" : "暂停检测"
        reconcileDetection()
    }
    @objc func cameraError() { statusMenuItem.title = "摄像头不可用，请暂停后重试"; setRadarIcon(nil); lastRenderedLevels = nil; hasRenderedLevels = true }
    @objc func willSleep() { lifecycle.sleeping = true; reconcileDetection() }
    @objc func didWake() { lifecycle.sleeping = false; reconcileDetection() }
    @objc func didLock() { lifecycle.locked = true; reconcileDetection() }
    @objc func didUnlock() { lifecycle.locked = false; reconcileDetection() }
    @objc func quit() { camera.stop(); NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
