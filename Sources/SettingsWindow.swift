import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController {
    unowned let app: AppDelegate
    private let regionView: RegionView
    private let picker = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let guideToggle = NSButton(checkboxWithTitle: "显示距离辅助线", target: nil, action: nil)
    private let statsLabel = NSTextField(labelWithString: "")
    private let toggle = NSButton(title: "", target: nil, action: nil)
    private let photoToggle = NSButton(checkboxWithTitle: "保存诊断照片（仅本机）", target: nil, action: nil)
    private let photoLabel = NSTextField(labelWithString: "")
    private let situation = NSPopUpButton()
    private let result = NSPopUpButton()
    private let stationary = NSTextField()
    private let sensitivity = NSPopUpButton()
    private let mirrorKey = NSTextField()
    private let pauseKey = NSTextField()
    private let hideKey = NSTextField()
    private let login = NSButton(checkboxWithTitle: "登录后自动启动", target: nil, action: nil)
    private let widthLabel = NSTextField(labelWithString: "")
    private let opacityLabel = NSTextField(labelWithString: "")
    private let workAppLabel = NSTextField(labelWithString: "")
    private let workAppMessage = NSTextField(labelWithString: "")
    private let autoSwitch = NSButton(checkboxWithTitle: "黄色或红色提醒时自动切换", target: nil, action: nil)
    private let testSwitch = NSButton(title: "测试切换", target: nil, action: nil)

    init(app: AppDelegate) {
        self.app = app
        regionView = RegionView(session: app.camera.session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "FishRadar 设置"; window.isReleasedWhenClosed = false
        super.init(window: window)
        let tabs = NSTabView(frame: NSRect(x: 12, y: 12, width: 676, height: 516))
        window.contentView?.addSubview(tabs)
        let general = NSTabViewItem(identifier: "general"); general.label = "常规"; general.view = generalPage(); tabs.addTabViewItem(general)
        let zones = NSTabViewItem(identifier: "zones"); zones.label = "检测区域与预览"; zones.view = regionPage(); tabs.addTabViewItem(zones)
        let switching = NSTabViewItem(identifier: "switching"); switching.label = "自动切换"; switching.view = switchPage(); tabs.addTabViewItem(switching)
        let monitor = NSTabViewItem(identifier: "monitor"); monitor.label = "实验监控"; monitor.view = monitorPage(); tabs.addTabViewItem(monitor)
        window.center(); updateStatus(app.currentStatus, levels: app.currentLevels); refreshDiagnostics()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text); l.frame = NSRect(x: x, y: y, width: width, height: 22); return l
    }
    private func field(_ value: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 90) -> NSTextField {
        let f = NSTextField(string: value); f.frame = NSRect(x: x, y: y, width: width, height: 24); return f
    }
    private func generalPage() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 475))
        let defaults = UserDefaults.standard
        let width = defaults.object(forKey: "mirrorWidth") as? Double ?? 180
        let opacity = defaults.object(forKey: "mirrorOpacity") as? Double ?? 1
        v.addSubview(label("后视镜大小", 20, 425, 110))
        let sizeSlider = NSSlider(value: width, minValue: 120, maxValue: 600, target: self, action: #selector(changeSize(_:)))
        sizeSlider.frame = NSRect(x: 145, y: 420, width: 310, height: 26); v.addSubview(sizeSlider)
        widthLabel.frame = NSRect(x: 470, y: 425, width: 150, height: 22); widthLabel.stringValue = "\(Int(width)) 点"; v.addSubview(widthLabel)
        v.addSubview(label("后视镜不透明度", 20, 380, 120))
        let opacitySlider = NSSlider(value: opacity, minValue: 0.2, maxValue: 1, target: self, action: #selector(changeOpacity(_:)))
        opacitySlider.frame = NSRect(x: 145, y: 375, width: 310, height: 26); v.addSubview(opacitySlider)
        opacityLabel.frame = NSRect(x: 470, y: 380, width: 150, height: 22); opacityLabel.stringValue = "\(Int(opacity * 100))%"; v.addSubview(opacityLabel)
        v.addSubview(label("拖动滑块会立即调整后视镜。", 20, 345, 300))
        let previewButton = NSButton(title: "显示/隐藏后视镜", target: app, action: #selector(AppDelegate.showMirror))
        previewButton.frame = NSRect(x: 350, y: 338, width: 160, height: 30); v.addSubview(previewButton)
        v.addSubview(label("静止忽略时间（秒）", 20, 295, 140))
        stationary.frame = NSRect(x: 170, y: 292, width: 90, height: 24); stationary.stringValue = String(Int(defaults.object(forKey: "stationarySeconds") as? Double ?? 5)); v.addSubview(stationary)
        v.addSubview(label("灵敏度", 300, 295, 70))
        sensitivity.frame = NSRect(x: 370, y: 290, width: 120, height: 26); sensitivity.addItems(withTitles: ["低", "中", "高"])
        let current = defaults.object(forKey: "sensitivity") as? Double ?? 1; sensitivity.selectItem(at: current < 0.9 ? 0 : current > 1.1 ? 2 : 1); v.addSubview(sensitivity)
        let keys = app.savedHotKeys()
        for (index, item) in [("⌃⌥ 后视镜", mirrorKey), ("⌃⌥ 暂停检测", pauseKey), ("⌃⌥ 显示/隐藏箭头", hideKey)].enumerated() {
            let y = CGFloat(245 - index * 37); v.addSubview(label(item.0, 20, y, 150)); item.1.frame = NSRect(x: 170, y: y - 3, width: 90, height: 24); item.1.stringValue = keys[index]; v.addSubview(item.1)
        }
        login.frame = NSRect(x: 300, y: 242, width: 240, height: 24)
        if #available(macOS 13.0, *) { login.state = SMAppService.mainApp.status == .enabled ? .on : .off } else { login.isEnabled = false }
        v.addSubview(login)
        let save = NSButton(title: "保存检测与快捷键设置", target: self, action: #selector(saveGeneral)); save.frame = NSRect(x: 20, y: 95, width: 220, height: 32); v.addSubview(save)
        v.addSubview(label("快捷键使用 Control + Option + 英文字母。", 20, 58, 550))
        return v
    }
    private func regionPage() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 475))
        picker.frame = NSRect(x: 15, y: 440, width: 145, height: 26); picker.addItems(withTitles: ["有效区域", "忽略区域", "重点区域"]); picker.target = self; picker.action = #selector(selectZone); v.addSubview(picker)
        v.addSubview(label("拖动绘制区域；按人员框中心判断。", 170, 442, 275))
        guideToggle.frame = NSRect(x: 465, y: 439, width: 178, height: 26)
        guideToggle.state = UserDefaults.standard.bool(forKey: "distanceGuides") ? .on : .off
        guideToggle.target = self; guideToggle.action = #selector(toggleDistanceGuides); v.addSubview(guideToggle)
        regionView.frame = NSRect(x: 15, y: 77, width: 630, height: 354); v.addSubview(regionView)
        regionView.zone = app.storedZone(app.zoneKeys[0])
        regionView.onChange = { [weak self] zone in
            guard let self = self else { return }
            let key = self.app.zoneKeys[self.picker.indexOfSelectedItem]
            if let zone { UserDefaults.standard.set(NSStringFromRect(zone), forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            self.app.applyDetectionSettings()
        }
        let clear = NSButton(title: "清除当前区域", target: self, action: #selector(clearZone)); clear.frame = NSRect(x: 15, y: 38, width: 130, height: 28); v.addSubview(clear)
        statusLabel.frame = NSRect(x: 160, y: 43, width: 480, height: 24); v.addSubview(statusLabel)
        v.addSubview(label("画面与后视镜同向；忽略区优先。状态：0 无、1 人、2 近处或靠近、3 更近。", 15, 10, 630))
        return v
    }
    private func switchPage() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 475))
        v.addSubview(label("工作应用", 20, 425, 100))
        workAppLabel.frame = NSRect(x: 120, y: 425, width: 325, height: 22); v.addSubview(workAppLabel)
        let choose = NSButton(title: "选择应用…", target: self, action: #selector(chooseWorkApp))
        choose.frame = NSRect(x: 460, y: 420, width: 120, height: 32); v.addSubview(choose)
        autoSwitch.frame = NSRect(x: 20, y: 370, width: 350, height: 24)
        autoSwitch.target = self; autoSwitch.action = #selector(toggleAutoSwitch); v.addSubview(autoSwitch)
        v.addSubview(label("任一方向进入黄色或红色时，切换到所选应用。", 20, 330, 620))
        v.addSubview(label("同一次提醒只切换一次；应用未运行时会自动打开。", 20, 300, 620))
        testSwitch.frame = NSRect(x: 20, y: 250, width: 120, height: 32)
        testSwitch.target = self; testSwitch.action = #selector(testWorkApp); v.addSubview(testSwitch)
        workAppMessage.frame = NSRect(x: 20, y: 210, width: 620, height: 22); v.addSubview(workAppMessage)
        refreshWorkApp()
        return v
    }
    private func monitorPage() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 475))
        v.addSubview(label("实验性监控与可靠性测试", 20, 430, 400))
        toggle.target = self; toggle.action = #selector(toggleDiagnostics); toggle.frame = NSRect(x: 20, y: 385, width: 140, height: 32); v.addSubview(toggle)
        statsLabel.frame = NSRect(x: 175, y: 390, width: 465, height: 22); v.addSubview(statsLabel)
        v.addSubview(label("记录 CPU、内存和帧率，并对照新旧距离判定。", 20, 350, 620))
        photoToggle.frame = NSRect(x: 20, y: 320, width: 300, height: 24)
        photoToggle.target = self; photoToggle.action = #selector(togglePhotos); v.addSubview(photoToggle)
        v.addSubview(label("箭头亮起或升级时抓拍，走动测试时也拍一张。", 20, 293, 620))
        let reveal = NSButton(title: "打开记录文件夹", target: self, action: #selector(revealLogs)); reveal.frame = NSRect(x: 20, y: 256, width: 150, height: 30); v.addSubview(reveal)
        v.addSubview(label("走动测试：选择场景和实际结果，手动记录。", 20, 220, 600))
        situation.frame = NSRect(x: 20, y: 185, width: 200, height: 26); situation.addItems(withTitles: ["左侧靠近", "右侧靠近", "无人活动", "多人出现", "人员被遮挡", "使用者离座", "忽略区内活动", "走出忽略区"]); v.addSubview(situation)
        result.frame = NSRect(x: 235, y: 185, width: 180, height: 26); result.addItems(withTitles: ["符合预期", "漏报", "误报", "方向错误", "不确定"]); v.addSubview(result)
        let record = NSButton(title: "记录本次测试", target: self, action: #selector(recordTrial)); record.frame = NSRect(x: 425, y: 181, width: 140, height: 30); v.addSubview(record)
        v.addSubview(label("记录包含你选择的结果和当时箭头状态；不会自动判断对错。", 20, 150, 620))
        v.addSubview(label("日志每份约 5 MiB，保留两份；照片最多 200 张，不自动删除。", 20, 115, 620))
        photoLabel.frame = NSRect(x: 20, y: 75, width: 620, height: 22); v.addSubview(photoLabel)
        return v
    }
    @objc private func changeSize(_ slider: NSSlider) {
        let width = Int(slider.doubleValue.rounded()); widthLabel.stringValue = "\(width) 点"
        UserDefaults.standard.set(width, forKey: "mirrorWidth")
        app.window.setContentSize(NSSize(width: CGFloat(width), height: CGFloat(width)*9/16))
    }
    @objc private func changeOpacity(_ slider: NSSlider) {
        let value = slider.doubleValue; opacityLabel.stringValue = "\(Int(value * 100))%"
        UserDefaults.standard.set(value, forKey: "mirrorOpacity"); app.window.alphaValue = value
    }
    @objc private func saveGeneral() {
        guard let seconds = Int(stationary.stringValue), (1...300).contains(seconds) else { showError("静止忽略时间请输入 1 到 300 之间的整数。"); return }
        let old = app.savedHotKeys()
        let keys = [mirrorKey.stringValue, pauseKey.stringValue, hideKey.stringValue].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        guard app.hotKeys.configure(keys) else { _ = app.hotKeys.configure(old); showError("快捷键无效或已被占用，请填写三个不同的英文字母。"); return }
        UserDefaults.standard.set(keys, forKey: "hotKeys"); UserDefaults.standard.set(seconds, forKey: "stationarySeconds")
        UserDefaults.standard.set([0.7, 1.0, 1.4][sensitivity.indexOfSelectedItem], forKey: "sensitivity")
        app.camera.setStationarySeconds(Double(seconds)); app.applyDetectionSettings()
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if login.state == .on && service.status != .enabled { try service.register() }
                if login.state == .off && service.status == .enabled { try service.unregister() }
                if login.state == .on && service.status != .enabled { throw NSError(domain: "FishRadar", code: 1, userInfo: [NSLocalizedDescriptionKey: "请在系统设置的登录项中确认。 "]) }
            } catch { showError("登录时启动未生效：\(error.localizedDescription)") }
        }
    }
    @objc private func selectZone() { regionView.zone = app.storedZone(app.zoneKeys[picker.indexOfSelectedItem]) }
    @objc private func toggleDistanceGuides() {
        let enabled = guideToggle.state == .on
        UserDefaults.standard.set(enabled, forKey: "distanceGuides")
        app.setDistanceGuides(enabled)
        if !enabled { regionView.showDistanceGuides(nil) }
    }
    func updateDistanceGuides(_ guides: DistanceGuideFrame?) {
        guard guideToggle.state == .on, regionView.window?.isVisible == true,
              !regionView.isHiddenOrHasHiddenAncestor else {
            regionView.showDistanceGuides(nil)
            return
        }
        regionView.showDistanceGuides(guides)
    }
    @objc private func clearZone() { UserDefaults.standard.removeObject(forKey: app.zoneKeys[picker.indexOfSelectedItem]); regionView.zone = nil; app.applyDetectionSettings() }
    @objc private func chooseWorkApp() {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.title = "选择工作应用"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url, Bundle(url: url)?.bundleIdentifier != nil else { return }
            UserDefaults.standard.set(url.path, forKey: "workAppPath")
            self.workAppMessage.stringValue = ""
            self.refreshWorkApp()
        }
    }
    @objc private func toggleAutoSwitch() { UserDefaults.standard.set(autoSwitch.state == .on, forKey: "automaticAppSwitch") }
    @objc private func testWorkApp() { workAppMessage.stringValue = ""; app.switchToWorkApp() }
    private func refreshWorkApp() {
        let path = UserDefaults.standard.string(forKey: "workAppPath")
        workAppLabel.stringValue = path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "未选择应用"
        autoSwitch.isEnabled = path != nil; testSwitch.isEnabled = path != nil
        autoSwitch.state = UserDefaults.standard.bool(forKey: "automaticAppSwitch") ? .on : .off
    }
    func setWorkAppMessage(_ message: String) { workAppMessage.stringValue = message }
    @objc private func toggleDiagnostics() { app.toggleResources() }
    @objc private func togglePhotos() { app.setPhotoCapture(photoToggle.state == .on) }
    @objc private func revealLogs() { NSWorkspace.shared.open(app.diagnostics.fileURL.deletingLastPathComponent()) }
    @objc private func recordTrial() {
        guard app.resourceTimer != nil else { showError("请先开启实验监控，再记录测试结果。"); return }
        let id = UUID().uuidString
        app.writeDiagnostic("trial", ["id": id, "scenario": situation.titleOfSelectedItem ?? "", "result": result.titleOfSelectedItem ?? "", "status": app.currentStatus, "left": app.currentLevels?.left ?? -1, "right": app.currentLevels?.right ?? -1])
        if app.savePhotos { app.captureDiagnosticPhoto(eventID: id, reason: "走动测试") }
        if app.resourceTimer != nil { statsLabel.stringValue = "已记录：\(situation.titleOfSelectedItem ?? "") · \(result.titleOfSelectedItem ?? "")" }
    }
    private func showError(_ text: String) { let alert = NSAlert(); alert.messageText = text; alert.runModal() }
    func setPhotoMessage(_ text: String) { photoLabel.stringValue = text }
    func setDiagnosticMessage(_ text: String) { statsLabel.stringValue = text; toggle.title = "开启监控" }
    func refreshDiagnostics() { photoToggle.state = app.savePhotos ? .on : .off; photoToggle.isEnabled = app.resourceTimer != nil; toggle.title = app.resourceTimer == nil ? "开启监控" : "停止监控"; statsLabel.stringValue = app.resourceItem?.title ?? "资源监控：关闭" }
    func updateStatus(_ status: String, levels: RadarLevels?) { statusLabel.stringValue = levels.map { "\(status) · 左 \($0.left) / 右 \($0.right)" } ?? status }
}
