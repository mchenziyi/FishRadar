import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    unowned let app: AppDelegate
    private let sidebar = NSTableView()
    private let pages = NSTabView()
    private static let contentSize = NSSize(width: 660, height: 500)
    private let pageSizes = [NSSize(width: 520, height: 390), SettingsWindowController.contentSize,
                             NSSize(width: 520, height: 270), NSSize(width: 550, height: 400)]
    private let regionView: RegionView
    private let picker = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let guideToggle = NSButton(checkboxWithTitle: "显示距离辅助线", target: nil, action: nil)
    private let guideLegend = NSView()
    private let statsLabel = NSTextField(labelWithString: "")
    private let toggle = NSButton(title: "", target: nil, action: nil)
    private let recordButton = NSButton(title: "记录本次测试", target: nil, action: nil)
    private let photoToggle = NSButton(checkboxWithTitle: "保存诊断照片（仅本机）", target: nil, action: nil)
    private let photoLimit = NSTextField()
    private let photoLabel = NSTextField(labelWithString: "")
    private let photoLimitMessage = NSTextField(labelWithString: "")
    private let situation = NSPopUpButton()
    private let result = NSPopUpButton()
    private let stationary = NSTextField()
    private let stationaryMessage = NSTextField(labelWithString: "")
    private let sensitivity = NSPopUpButton()
    private let mirrorKey = NSTextField()
    private let pauseKey = NSTextField()
    private let hideKey = NSTextField()
    private let login = NSButton(checkboxWithTitle: "登录后自动启动", target: nil, action: nil)
    private let loginMessage = NSTextField(labelWithString: "")
    private let shortcutMessage = NSTextField(labelWithString: "")
    private let widthLabel = NSTextField(labelWithString: "")
    private let opacityLabel = NSTextField(labelWithString: "")
    private let workAppLabel = NSTextField(labelWithString: "")
    private let workAppMessage = NSTextField(labelWithString: "")
    private let autoSwitch = NSButton(checkboxWithTitle: "黄色或红色提醒时自动切换", target: nil, action: nil)
    private let testSwitch = NSButton(title: "测试切换", target: nil, action: nil)

    init(app: AppDelegate) {
        self.app = app
        regionView = RegionView(session: app.camera.session)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.contentSize.width + 164, height: Self.contentSize.height + 24),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "FishRadar 设置"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        pages.frame = pageFrame(at: 0)
        pages.tabViewType = .noTabsNoBorder
        window.contentView?.addSubview(pages)
        let general = NSTabViewItem(identifier: "general"); general.label = "常规"; general.view = generalPage(); pages.addTabViewItem(general)
        let zones = NSTabViewItem(identifier: "zones"); zones.label = "检测区域与预览"; zones.view = regionPage(); pages.addTabViewItem(zones)
        let switching = NSTabViewItem(identifier: "switching"); switching.label = "自动切换"; switching.view = switchPage(); pages.addTabViewItem(switching)
        let monitor = NSTabViewItem(identifier: "monitor"); monitor.label = "实验监控"; monitor.view = monitorPage(); pages.addTabViewItem(monitor)
        window.contentView?.addSubview(makeSidebar())
        sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.center(); updateStatus(app.currentStatus, levels: app.currentLevels); refreshDiagnostics()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeSidebar() -> NSView {
        let height = Self.contentSize.height + 24
        let panel = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 140, height: height))
        panel.material = .sidebar
        panel.blendingMode = .withinWindow
        panel.autoresizingMask = [.height]

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("settings"))
        sidebar.addTableColumn(column)
        sidebar.headerView = nil
        sidebar.backgroundColor = .clear
        if #available(macOS 11.0, *) { sidebar.style = .sourceList }
        sidebar.rowHeight = 32
        sidebar.allowsEmptySelection = false
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.setAccessibilityLabel("设置分类")

        let scroll = NSScrollView(frame: NSRect(x: 6, y: height - 155, width: 129, height: 144))
        scroll.autoresizingMask = [.minYMargin]
        scroll.drawsBackground = false
        scroll.documentView = sidebar
        sidebar.sizeLastColumnToFit()
        panel.addSubview(scroll)
        let divider = NSBox(frame: NSRect(x: 139, y: 0, width: 1, height: height))
        divider.boxType = .separator
        divider.autoresizingMask = [.height]
        panel.addSubview(divider)
        return panel
    }

    func numberOfRows(in tableView: NSTableView) -> Int { pages.numberOfTabViewItems }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: pages.tabViewItems[row].label)
        title.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(title)
        cell.textField = title
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5),
            title.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func pageFrame(at row: Int) -> NSRect {
        let size = pageSizes[row]
        return NSRect(x: 152, y: 12 + Self.contentSize.height - size.height, width: size.width, height: size.height)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebar.selectedRow
        guard let window, pageSizes.indices.contains(row) else { return }
        window.makeFirstResponder(sidebar)
        pages.frame = pageFrame(at: row)
        pages.selectTabViewItem(at: row)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil)
        return true
    }

    private func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text); l.frame = NSRect(x: x, y: y, width: width, height: 22); return l
    }
    private func section(_ title: String, _ y: CGFloat) -> NSTextField {
        let heading = label(title, 18, y, 260)
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        return heading
    }
    private func field(_ value: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 90) -> NSTextField {
        let f = NSTextField(string: value); f.frame = NSRect(x: x, y: y, width: width, height: 24); return f
    }
    private func separator(_ y: CGFloat, on page: NSView) {
        let line = NSBox(frame: NSRect(x: 18, y: y, width: page.bounds.width - 36, height: 1))
        line.boxType = .separator
        page.addSubview(line)
    }
    private func feedback(_ field: NSTextField, _ frame: NSRect, on page: NSView) {
        field.frame = frame
        field.textColor = .systemRed
        page.addSubview(field)
    }
    private func generalPage() -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: pageSizes[0]))
        let defaults = UserDefaults.standard
        let width = defaults.object(forKey: "mirrorWidth") as? Double ?? 180
        let opacity = defaults.object(forKey: "mirrorOpacity") as? Double ?? 1
        v.addSubview(section("后视镜", 352))
        let previewButton = NSButton(title: "显示或隐藏后视镜", target: app, action: #selector(AppDelegate.showMirror))
        previewButton.frame = NSRect(x: 350, y: 348, width: 152, height: 30)
        v.addSubview(previewButton)

        v.addSubview(label("大小", 18, 316, 130))
        let size = NSSlider(value: width, minValue: 120, maxValue: 600, target: self, action: #selector(changeSize(_:)))
        size.isContinuous = true
        size.frame = NSRect(x: 202, y: 313, width: 231, height: 26)
        size.setAccessibilityLabel("后视镜大小")
        v.addSubview(size)
        widthLabel.frame = NSRect(x: 447, y: 316, width: 55, height: 22)
        widthLabel.alignment = .right
        widthLabel.stringValue = "\(Int(width)) 点"
        v.addSubview(widthLabel)

        v.addSubview(label("不透明度", 18, 280, 130))
        let alpha = NSSlider(value: opacity, minValue: 0.2, maxValue: 1, target: self, action: #selector(changeOpacity(_:)))
        alpha.isContinuous = true
        alpha.frame = NSRect(x: 202, y: 277, width: 231, height: 26)
        alpha.setAccessibilityLabel("后视镜不透明度")
        v.addSubview(alpha)
        opacityLabel.frame = NSRect(x: 447, y: 280, width: 55, height: 22)
        opacityLabel.alignment = .right
        opacityLabel.stringValue = "\(Int(opacity * 100))%"
        v.addSubview(opacityLabel)

        separator(263, on: v)
        v.addSubview(section("全局快捷键", 228))
        let modifiers = label("Control + Option + 字母", 289, 228, 213)
        modifiers.alignment = .right
        modifiers.textColor = .secondaryLabelColor
        v.addSubview(modifiers)
        let keys = app.savedHotKeys()
        for (index, item) in [("后视镜", mirrorKey), ("暂停或恢复检测", pauseKey), ("显示或隐藏箭头", hideKey)].enumerated() {
            let y = CGFloat(196 - index * 33)
            v.addSubview(label(item.0, 18, y, 185))
            item.1.frame = NSRect(x: 445, y: y - 2, width: 57, height: 24)
            item.1.alignment = .center
            item.1.stringValue = keys[index]
            item.1.delegate = self
            item.1.setAccessibilityLabel(item.0)
            v.addSubview(item.1)
        }
        feedback(shortcutMessage, NSRect(x: 18, y: 104, width: 484, height: 22), on: v)
        separator(92, on: v)

        v.addSubview(section("启动", 58))
        login.frame = NSRect(x: 18, y: 24, width: 180, height: 24)
        login.target = self
        login.action = #selector(changeLogin)
        v.addSubview(login)
        feedback(loginMessage, NSRect(x: 206, y: 24, width: 296, height: 22), on: v)
        refreshLogin()
        return v
    }

    private func regionPage() -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: pageSizes[1]))
        statusLabel.frame = NSRect(x: 16, y: 464, width: 430, height: 22)
        v.addSubview(statusLabel)
        guideToggle.frame = NSRect(x: 488, y: 462, width: 158, height: 26)
        guideToggle.state = UserDefaults.standard.bool(forKey: "distanceGuides") ? .on : .off
        guideToggle.target = self
        guideToggle.action = #selector(toggleDistanceGuides)
        v.addSubview(guideToggle)

        regionView.frame = NSRect(x: 16, y: 102, width: 628, height: 353)
        regionView.layer?.backgroundColor = NSColor.black.cgColor
        regionView.layer?.cornerRadius = 8
        regionView.layer?.masksToBounds = true
        v.addSubview(regionView)
        regionView.zone = app.storedZone(app.zoneKeys[0])
        regionView.onChange = { [weak self] zone in
            guard let self else { return }
            let key = self.app.zoneKeys[self.picker.indexOfSelectedItem]
            if let zone { UserDefaults.standard.set(NSStringFromRect(zone), forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            self.app.applyDetectionSettings()
        }

        picker.frame = NSRect(x: 16, y: 68, width: 128, height: 26)
        picker.addItems(withTitles: ["有效区域", "忽略区域", "重点区域"])
        picker.target = self
        picker.action = #selector(selectZone)
        v.addSubview(picker)
        let clear = NSButton(title: "清除当前区域", target: self, action: #selector(clearZone))
        clear.frame = NSRect(x: 152, y: 66, width: 122, height: 30)
        v.addSubview(clear)
        let hint = label("在画面上拖动绘制。忽略区优先。", 295, 69, 349)
        hint.alignment = .right
        hint.textColor = .secondaryLabelColor
        v.addSubview(hint)
        separator(60, on: v)

        v.addSubview(label("灵敏度", 16, 31, 58))
        sensitivity.frame = NSRect(x: 76, y: 27, width: 92, height: 26)
        sensitivity.addItems(withTitles: ["低", "中", "高"])
        let current = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1
        sensitivity.selectItem(at: current < 0.9 ? 0 : current > 1.1 ? 2 : 1)
        sensitivity.target = self
        sensitivity.action = #selector(changeSensitivity)
        sensitivity.setAccessibilityLabel("灵敏度")
        v.addSubview(sensitivity)
        v.addSubview(label("静止忽略时间（秒）", 203, 31, 137))
        stationary.frame = NSRect(x: 347, y: 29, width: 62, height: 24)
        stationary.stringValue = String(Int(UserDefaults.standard.object(forKey: "stationarySeconds") as? Double ?? 5))
        stationary.identifier = NSUserInterfaceItemIdentifier("stationarySeconds")
        stationary.setAccessibilityLabel("静止忽略时间（秒）")
        stationary.delegate = self
        v.addSubview(stationary)
        feedback(stationaryMessage, NSRect(x: 423, y: 30, width: 220, height: 22), on: v)

        guideLegend.frame = NSRect(x: 16, y: 3, width: 630, height: 22)
        for (text, color, x) in [("蓝 · 自己头部", NSColor.systemBlue, 0),
                                 ("红 · 自己上半身", NSColor.systemRed, 114),
                                 ("青 · 参与检测", NSColor.systemTeal, 248)] {
            let item = label(text, CGFloat(x), 0, 130)
            item.textColor = color
            item.font = .systemFont(ofSize: 11)
            guideLegend.addSubview(item)
        }
        guideLegend.isHidden = guideToggle.state != .on
        v.addSubview(guideLegend)
        return v
    }

    private func switchPage() -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: pageSizes[2]))
        v.addSubview(section("工作应用", 231))
        workAppLabel.frame = NSRect(x: 18, y: 194, width: 350, height: 22)
        v.addSubview(workAppLabel)
        let choose = NSButton(title: "选择应用…", target: self, action: #selector(chooseWorkApp))
        choose.frame = NSRect(x: 378, y: 189, width: 124, height: 30)
        v.addSubview(choose)
        separator(173, on: v)

        v.addSubview(section("触发条件", 139))
        autoSwitch.frame = NSRect(x: 18, y: 104, width: 320, height: 24)
        autoSwitch.target = self
        autoSwitch.action = #selector(toggleAutoSwitch)
        v.addSubview(autoSwitch)
        let hint = label("同一次提醒只切换一次。应用未运行时会自动打开。", 18, 73, 484)
        hint.textColor = .secondaryLabelColor
        v.addSubview(hint)
        testSwitch.frame = NSRect(x: 382, y: 21, width: 120, height: 30)
        testSwitch.target = self
        testSwitch.action = #selector(testWorkApp)
        v.addSubview(testSwitch)
        workAppMessage.frame = NSRect(x: 18, y: 25, width: 346, height: 22)
        v.addSubview(workAppMessage)
        refreshWorkApp()
        return v
    }

    private func monitorPage() -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: pageSizes[3]))
        v.addSubview(section("资源采样", 362))
        toggle.target = self
        toggle.action = #selector(toggleDiagnostics)
        toggle.frame = NSRect(x: 417, y: 322, width: 115, height: 30)
        v.addSubview(toggle)
        statsLabel.frame = NSRect(x: 18, y: 327, width: 383, height: 22)
        v.addSubview(statsLabel)
        separator(310, on: v)

        v.addSubview(section("诊断抓拍", 276))
        photoToggle.frame = NSRect(x: 18, y: 243, width: 278, height: 24)
        photoToggle.target = self
        photoToggle.action = #selector(togglePhotos)
        v.addSubview(photoToggle)
        v.addSubview(label("照片上限（张）", 18, 209, 132))
        photoLimit.frame = NSRect(x: 452, y: 207, width: 80, height: 24)
        photoLimit.stringValue = String(app.diagnosticPhotoLimit)
        photoLimit.identifier = NSUserInterfaceItemIdentifier("diagnosticPhotoLimit")
        photoLimit.setAccessibilityLabel("照片上限（张）")
        photoLimit.delegate = self
        v.addSubview(photoLimit)
        feedback(photoLimitMessage, NSRect(x: 168, y: 208, width: 270, height: 22), on: v)
        photoLabel.frame = NSRect(x: 18, y: 179, width: 514, height: 22)
        v.addSubview(photoLabel)
        separator(163, on: v)

        v.addSubview(section("走动测试", 130))
        situation.frame = NSRect(x: 18, y: 95, width: 190, height: 26)
        situation.addItems(withTitles: ["左侧靠近", "右侧靠近", "无人活动", "多人出现", "人员被遮挡", "使用者离座", "忽略区内活动", "走出忽略区"])
        situation.setAccessibilityLabel("测试场景")
        v.addSubview(situation)
        result.frame = NSRect(x: 219, y: 95, width: 169, height: 26)
        result.addItems(withTitles: ["符合预期", "漏报", "误报", "方向错误", "不确定"])
        result.setAccessibilityLabel("测试结果")
        v.addSubview(result)
        recordButton.target = self
        recordButton.action = #selector(recordTrial)
        recordButton.frame = NSRect(x: 401, y: 92, width: 131, height: 30)
        v.addSubview(recordButton)
        separator(75, on: v)

        let reveal = NSButton(title: "打开记录文件夹", target: self, action: #selector(revealLogs))
        reveal.frame = NSRect(x: 377, y: 26, width: 155, height: 30)
        v.addSubview(reveal)
        let retention = label("日志约 5 MiB 一份，保留最近两份。", 18, 30, 340)
        retention.textColor = .secondaryLabelColor
        v.addSubview(retention)
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
    @objc private func changeSensitivity() {
        let values = [0.7, 1.0, 1.4]
        guard values.indices.contains(sensitivity.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(values[sensitivity.indexOfSelectedItem], forKey: "sensitivity")
        app.applyDetectionSettings()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              (notification.userInfo?["NSTextMovement"] as? Int) != NSCancelTextMovement else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case stationary:
            guard let seconds = Int(value), (1...300).contains(seconds) else {
                stationaryMessage.stringValue = "请输入 1–300 的整数。"
                return
            }
            UserDefaults.standard.set(seconds, forKey: "stationarySeconds")
            app.camera.setStationarySeconds(Double(seconds))
            stationary.stringValue = String(seconds)
            stationaryMessage.stringValue = ""
        case photoLimit:
            guard let count = Int(value), count > 0 else {
                photoLimitMessage.stringValue = "请输入大于 0 的整数。"
                return
            }
            app.diagnosticPhotoLimit = count
            photoLimit.stringValue = String(count)
            photoLimitMessage.stringValue = ""
        case mirrorKey, pauseKey, hideKey:
            applyShortcuts()
        default:
            break
        }
    }

    private func applyShortcuts() {
        let fields = [mirrorKey, pauseKey, hideKey]
        let keys = fields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        guard Set(keys).count == 3, keys.allSatisfy({ $0.utf8.count == 1 && (65...90).contains($0.utf8.first!) }) else {
            shortcutMessage.stringValue = "请为三个快捷键填写不同的英文字母。"
            return
        }
        let old = app.savedHotKeys()
        if keys != old {
            guard app.hotKeys.configure(keys) else {
                _ = app.hotKeys.configure(old)
                shortcutMessage.stringValue = "该快捷键已被占用，请换一个字母。"
                return
            }
            UserDefaults.standard.set(keys, forKey: "hotKeys")
        }
        for (field, key) in zip(fields, keys) { field.stringValue = key }
        shortcutMessage.stringValue = ""
    }

    private func refreshLogin() {
        guard #available(macOS 13.0, *) else { login.isEnabled = false; return }
        let status = SMAppService.mainApp.status
        login.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginMessage.stringValue = status == .requiresApproval ? "请在系统设置的登录项中允许 FishRadar。" : ""
    }

    @objc private func changeLogin() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            let requested = login.state == .on
            let registered = service.status == .enabled || service.status == .requiresApproval
            if requested && !registered { try service.register() }
            if !requested && registered { try service.unregister() }
            refreshLogin()
        } catch {
            refreshLogin()
            loginMessage.stringValue = "登录项修改失败：\(error.localizedDescription)"
        }
    }
    @objc private func selectZone() { regionView.zone = app.storedZone(app.zoneKeys[picker.indexOfSelectedItem]) }
    @objc private func toggleDistanceGuides() {
        let enabled = guideToggle.state == .on
        UserDefaults.standard.set(enabled, forKey: "distanceGuides")
        app.setDistanceGuides(enabled)
        guideLegend.isHidden = !enabled
        if !enabled { regionView.showDistanceGuides(nil) }
    }
    var isDistancePreviewVisible: Bool {
        guideToggle.state == .on && regionView.window?.isVisible == true && !regionView.isHiddenOrHasHiddenAncestor
    }
    func updateDistanceGuides(_ guides: DistanceGuideFrame?) {
        guard isDistancePreviewVisible else {
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
    func refreshDiagnostics() {
        let monitoring = app.resourceTimer != nil
        photoToggle.state = app.savePhotos ? .on : .off
        photoToggle.isEnabled = monitoring
        recordButton.isEnabled = monitoring
        toggle.title = monitoring ? "停止监控" : "开启监控"
        statsLabel.stringValue = app.resourceItem?.title ?? "资源监控：关闭"
    }
    func updateStatus(_ status: String, levels: RadarLevels?) {
        let names = ["白", "绿", "黄", "红"]
        statusLabel.stringValue = levels.map { "\(status) · 左\(names[$0.left]) / 右\(names[$0.right])" } ?? status
    }
}
