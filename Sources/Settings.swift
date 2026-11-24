import AppKit
import ServiceManagement
import Darwin

extension AppDelegate {
    var zoneKeys: [String] { ["effectiveZone", "ignoreZone", "focusZone"] }
    func storedZone(_ key: String) -> CGRect? {
        guard let s = UserDefaults.standard.string(forKey: key) else { return nil }
        let r = NSRectFromString(s)
        return r.width > 0 && r.height > 0 ? r : nil
    }
    func applyDetectionSettings() {
        let sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1
        camera.updateConfiguration(effective: storedZone(zoneKeys[0]), ignore: storedZone(zoneKeys[1]), focus: storedZone(zoneKeys[2]), sensitivity: sensitivity)
    }
    func restorePosition(_ window: NSWindow, key: String) {
        guard let value = UserDefaults.standard.string(forKey: key) else { return }
        let point = NSPointFromString(value)
        let frame = NSRect(origin: point, size: window.frame.size)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { window.setFrameOrigin(point) }
    }
    func snapAndSave(_ window: NSWindow, key: String) {
        if let screen = window.screen {
            let area = screen.visibleFrame
            var frame = window.frame
            let gap: CGFloat = 16
            if abs(frame.minX - area.minX) < gap { frame.origin.x = area.minX }
            if abs(frame.maxX - area.maxX) < gap { frame.origin.x = area.maxX - frame.width }
            if abs(frame.minY - area.minY) < gap { frame.origin.y = area.minY }
            if abs(frame.maxY - area.maxY) < gap { frame.origin.y = area.maxY - frame.height }
            window.setFrameOrigin(frame.origin)
        }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: key)
    }
    func savedHotKeys() -> [String] { UserDefaults.standard.stringArray(forKey: "hotKeys") ?? ["R", "P", "H"] }
    @objc func showSettings() {
        if settingsController == nil { settingsController = SettingsWindowController(app: self) }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }
    func writeDiagnostic(_ type: String, _ values: [String: Any]) {
        do { try diagnostics.write(type, values) }
        catch {
            resourceTimer?.invalidate(); resourceTimer = nil; lastUsage = nil
            setPhotoCapture(false)
            resourceItem?.title = "资源监控：记录失败"
            settingsController?.setDiagnosticMessage("记录失败：\(error.localizedDescription)")
        }
    }
    func setPhotoCapture(_ enabled: Bool) {
        savePhotos = enabled
        photoGeneration += 1
        camera.setAutomaticPhotos(generation: enabled ? photoGeneration : nil)
        settingsController?.refreshDiagnostics()
    }
    func captureDiagnosticPhoto(eventID: String, reason: String) {
        guard savePhotos, resourceTimer != nil else { return }
        let generation = photoGeneration
        camera.requestPhoto { [weak self] result in
            self?.saveDiagnosticPhoto(result, generation: generation, eventID: eventID, reason: reason, boxes: nil)
        }
    }
    func saveDiagnosticPhoto(_ result: Result<Data, Error>, generation: Int, eventID: String, reason: String, boxes: [[String: Any]]?) {
        guard savePhotos, resourceTimer != nil, photoGeneration == generation else { return }
        do {
            let data = try result.get()
            let path = try diagnostics.savePhoto(data)
            var values: [String: Any] = ["event_id": eventID, "reason": reason, "file": path]
            if let boxes { values["boxes"] = boxes; values["coordinates"] = "unmirrored_bottom_left" }
            writeDiagnostic("photo", values)
            settingsController?.setPhotoMessage("照片已保存：\(path)")
        } catch {
            setPhotoCapture(false)
            settingsController?.setPhotoMessage("照片保存已停止：\(error.localizedDescription)")
            writeDiagnostic("photo_error", ["event_id": eventID, "reason": error.localizedDescription])
        }
    }
    @objc func toggleResources() {
        if resourceTimer != nil {
            resourceGeneration += 1
            writeDiagnostic("monitor_stop", [:])
            resourceTimer?.invalidate(); resourceTimer = nil; lastUsage = nil; resourceItem?.title = "资源监控：关闭"
            setPhotoCapture(false)
            settingsController?.refreshDiagnostics(); return
        }
        do { try diagnostics.write("monitor_start", [:]) } catch {
            resourceItem?.title = "资源监控：记录失败"
            settingsController?.setDiagnosticMessage("记录失败：\(error.localizedDescription)"); return
        }
        lastLoggedStatus = nil; lastLoggedLevels = nil
        resourceGeneration += 1
        camera.resetFrameSample()
        resourceItem?.title = "资源监控：采样中…"
        resourceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sampleResources() }
        sampleResources()
        settingsController?.refreshDiagnostics()
    }
    private func sampleResources() {
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let now = Date(); var title = "资源监控："
        var values: [String: Any] = [:]
        if let previous = lastUsage {
            let elapsed = now.timeIntervalSince(previous.0)
            if elapsed > 0 { let percent = max(0, (cpu-previous.1)/elapsed*100); title += String(format: "CPU %.1f%%  ", percent); values["cpu_percent"] = percent }
        }
        if result == KERN_SUCCESS { let memory = Double(info.resident_size)/1_048_576; title += String(format: "内存 %.1f MiB", memory); values["resident_mib"] = memory }
        else { title += "内存不可用" }
        let generation = resourceGeneration
        let sampleValues = values
        camera.frameMetrics { [weak self] metrics in
            guard let self = self, self.resourceTimer != nil, self.resourceGeneration == generation else { return }
            var combined = sampleValues
            combined.merge(metrics) { _, new in new }
            self.writeDiagnostic("resources", combined)
        }
        if resourceTimer != nil { resourceItem?.title = title; settingsController?.refreshDiagnostics() }
        lastUsage = (now, cpu)
    }
}
