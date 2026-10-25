import AppKit
import ServiceManagement
import Carbon.HIToolbox
import ApplicationServices
import CryptoKit

// MARK: - 数据模型

struct ClipItem: Codable {
    var text: String          // 文本内容；图片=「🖼 md5」；文件=「📄 各文件完整路径」
    var added: Date
    var isTemp: Bool          // 临时条目（语音转文字/程序写入），15 分钟后自动清理
    var isPinned: Bool = false
    var kind: String = "text"        // text | image | file
    var imageFile: String? = nil     // 图片存盘路径（PNG）
    var filePaths: [String]? = nil   // 文件类型的完整路径

    init(text: String, added: Date, isTemp: Bool, isPinned: Bool = false,
         kind: String = "text", imageFile: String? = nil, filePaths: [String]? = nil) {
        self.text = text; self.added = added; self.isTemp = isTemp; self.isPinned = isPinned
        self.kind = kind; self.imageFile = imageFile; self.filePaths = filePaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        added = try c.decode(Date.self, forKey: .added)
        isTemp = try c.decode(Bool.self, forKey: .isTemp)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
        filePaths = try c.decodeIfPresent([String].self, forKey: .filePaths)
    }
}

// 抓取到的一条新剪贴板内容（观察期暂存用）
struct IncomingClip {
    var text: String
    var kind: String
    var imageFile: String?
    var filePaths: [String]?
}

// MARK: - 历史卡片（Win+V 风格的框框）

final class ClipCardView: NSView {
    let item: ClipItem
    var onCopy: (ClipItem) -> Void
    var onPin: (String) -> Void
    var onDelete: (String) -> Void

    private var mainView: NSView
    private let pinMark: NSTextField
    private let delMark: NSTextField
    private var tracking: NSTrackingArea?
    private var hovered = false { didSet { applyLook() } }
    private let isImage: Bool

    static func makeLabel(_ text: String, lines: Int) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 13)
        l.textColor = .labelColor
        l.isSelectable = false
        l.drawsBackground = false
        l.maximumNumberOfLines = lines
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    init(item: ClipItem,
         onCopy: @escaping (ClipItem) -> Void,
         onPin: @escaping (String) -> Void,
         onDelete: @escaping (String) -> Void) {
        self.item = item
        self.onCopy = onCopy; self.onPin = onPin; self.onDelete = onDelete
        isImage = item.kind == "image"

        switch item.kind {
        case "image":
            let iv = NSImageView()
            if let f = item.imageFile { iv.image = NSImage(contentsOfFile: f) }
            iv.imageScaling = .scaleProportionallyUpOrDown
            mainView = iv
        case "file":
            let names = (item.filePaths ?? []).map { ($0 as NSString).lastPathComponent }.joined(separator: "、")
            var n = names
            if n.count > 160 { n = String(n.prefix(160)) + "…" }
            mainView = Self.makeLabel("📄 " + (n.isEmpty ? "（文件）" : n), lines: 2)
        default:
            var prefix = ""
            if item.isPinned { prefix = "📌 " } else if item.isTemp { prefix = "💬 " }
            var body = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.count > 300 { body = String(body.prefix(300)) + "…" }
            mainView = Self.makeLabel(prefix + (body.isEmpty ? "（空白）" : body), lines: 3)
        }

        pinMark = NSTextField(labelWithString: "📌")
        pinMark.font = .systemFont(ofSize: 12)
        pinMark.alphaValue = 0
        pinMark.toolTip = item.isPinned ? "点击取消置顶" : "点击置顶"

        delMark = NSTextField(labelWithString: "✕")
        delMark.font = .systemFont(ofSize: 12)
        delMark.textColor = .secondaryLabelColor
        delMark.alphaValue = 0
        delMark.toolTip = "删除这条记录"

        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainView)
        addSubview(pinMark)
        addSubview(delMark)

        if isImage {
            // 图片卡片：图占满，右上角小状态标
            let badge = NSTextField(labelWithString: (item.isPinned ? "📌" : "") + (item.isTemp ? "💬" : ""))
            badge.font = .systemFont(ofSize: 11)
            badge.textColor = .secondaryLabelColor
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                mainView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                mainView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                mainView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                mainView.heightAnchor.constraint(equalToConstant: 96),
                heightAnchor.constraint(greaterThanOrEqualToConstant: 112),
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
                delMark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                delMark.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                pinMark.trailingAnchor.constraint(equalTo: delMark.leadingAnchor, constant: -6),
                pinMark.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            ])
        } else {
            NSLayoutConstraint.activate([
                mainView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
                mainView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                mainView.trailingAnchor.constraint(equalTo: pinMark.leadingAnchor, constant: -8),

                delMark.centerYAnchor.constraint(equalTo: centerYAnchor),
                delMark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                pinMark.centerYAnchor.constraint(equalTo: centerYAnchor),
                pinMark.trailingAnchor.constraint(equalTo: delMark.leadingAnchor, constant: -6),

                heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                bottomAnchor.constraint(greaterThanOrEqualTo: mainView.bottomAnchor, constant: 10),
            ])
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked(_:)))
        addGestureRecognizer(click)
        applyLook()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    @objc private func clicked(_ g: NSClickGestureRecognizer) {
        let p = g.location(in: self)
        if pinMark.frame.insetBy(dx: -6, dy: -6).contains(p) { onPin(item.text); return }
        if delMark.frame.insetBy(dx: -6, dy: -6).contains(p) { onDelete(item.text); return }
        onCopy(item)
    }

    private func applyLook() {
        let base: CGFloat = hovered ? 0.14 : 0.06
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(base).cgColor
        pinMark.alphaValue = hovered ? 1 : (item.isPinned ? 0.55 : 0)
        delMark.alphaValue = hovered ? 1 : 0
    }
}

// MARK: - 主逻辑

final class AppDelegate: NSObject, NSApplicationDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var panel: NSPanel!
    var stackView: NSStackView!
    var scrollView: NSScrollView!
    var searchField: NSSearchField!
    var loginCheckbox: NSButton!
    var pasteCheckbox: NSButton!
    var hintField: NSTextField!            // 面板顶部的授权/状态提示条
    var headerTopWithHint: NSLayoutConstraint!
    var headerTopNoHint: NSLayoutConstraint!
    var eventMonitors: [Any] = []
    var hotKeyRef: EventHotKeyRef?
    var previousApp: NSRunningApplication?   // 弹面板前的前台应用（自动粘贴目标）
    let kAutoPaste = "clip_autopaste"        // 默认开

    let maxHistory = 500
    let tempLifetime: TimeInterval = 15 * 60
    let maxImageBytes = 25_000_000           // 超大图片不入库

    var history: [ClipItem] = []   // 置顶在最前，其余最新在前
    var lastChangeCount = NSPasteboard.general.changeCount
    var recentWrites: [(text: String, time: Date)] = []
    var lastAXState = false                 // 辅助功能权限状态追踪（状态翻转时记日志）
    var lastAXCheckAt: TimeInterval = -10   // 权限查询节流（2 秒一次）
    // 新条目先扣 2.5 秒再入库：等"还原"动作出现好直接拦截语音条目
    var pending: (clip: IncomingClip, added: Date, userCopy: Bool)?
    var pendingTimer: Timer?

    var imagesDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("剪贴板助手/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    let kHistoryV3 = "clip_history_v3"
    let kHistoryV2 = "clip_history_v2"
    let kPinnedV2 = "clip_pinned"

    func log(_ s: String) {
        let path = "/tmp/cliphelper.log"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64, size > 1_000_000 {
            try? FileManager.default.removeItem(atPath: path)
        }
        let line = "\(Date()) \(s)\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!); try? fh.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: 启动
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "📋"
        statusItem.length = 30
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp])

        loadStore()
        log("历史读取完成：\(history.count) 条（置顶 \(history.filter { $0.isPinned }.count)，图片 \(history.filter { $0.kind == "image" }.count)）")

        if let cur = NSPasteboard.general.string(forType: .string) {
            recentWrites.append((cur, Date()))
        }

        buildPanel()
        registerHotKey()

        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        log("启动完成 v3.3（文本+图片+文件，⌥V 面板，延迟入库过滤）")

        // 调试：CLIP_DEBUG_SHOW=1 时启动 3 秒后自动弹出面板
        if ProcessInfo.processInfo.environment["CLIP_DEBUG_SHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.showPanel()
            }
        }
    }

    // MARK: 全局快捷键 ⌥V
    func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if id.id == 1 {
                DispatchQueue.main.async { gDelegate.togglePanel() }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        var hkID = EventHotKeyID(signature: OSType(0x434C5048) /* 'CLPH' */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(optionKey), hkID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: 面板
    func buildPanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                        styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 锁死面板尺寸，防止 AppKit 按内容最小适配尺寸压缩窗口
        panel.contentMinSize = NSSize(width: 420, height: 560)
        panel.contentMaxSize = NSSize(width: 420, height: 560)

        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
        vfx.material = .popover
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 12
        vfx.layer?.masksToBounds = true
        vfx.autoresizingMask = [.width, .height]
        panel.contentView = vfx
        panel.delegate = self
        // 关键修复：用约束把背景视图钉死在窗口内容区，布局引擎就不会擅自改窗口尺寸
        vfx.translatesAutoresizingMaskIntoConstraints = false
        let guide = panel.contentLayoutGuide as! NSLayoutGuide
        NSLayoutConstraint.activate([
            vfx.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            vfx.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            vfx.topAnchor.constraint(equalTo: guide.topAnchor),
            vfx.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])

        let header = NSTextField(labelWithString: "剪贴板历史 · 快捷键 ⌥V 呼出 / 收起")
        header.font = .systemFont(ofSize: 11)
        header.textColor = .secondaryLabelColor

        // 顶部提示条：缺辅助功能权限等关键状态提醒（可点击）
        hintField = NSTextField(wrappingLabelWithString: "")
        hintField.font = .systemFont(ofSize: 11)
        hintField.textColor = .systemOrange
        hintField.isSelectable = false
        hintField.drawsBackground = false
        hintField.translatesAutoresizingMaskIntoConstraints = false
        hintField.isHidden = true
        hintField.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openAccessibilitySettings)))

        searchField = NSSearchField()
        searchField.placeholderString = "搜索历史记录"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = .systemFont(ofSize: 13)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        let clearBtn = NSButton(title: "清空历史", target: self, action: #selector(clearAll))
        let quitBtn = NSButton(title: "退出", target: self, action: #selector(quitApp))
        loginCheckbox = NSButton(checkboxWithTitle: "开机自启", target: self, action: #selector(toggleLogin))
        pasteCheckbox = NSButton(checkboxWithTitle: "自动粘贴", target: self, action: #selector(toggleAutoPaste))
        pasteCheckbox.toolTip = "点卡片后自动粘贴到刚才的输入框（需辅助功能权限）"
        let footerButtons: [NSButton] = [clearBtn, loginCheckbox, pasteCheckbox, quitBtn]
        for b in footerButtons {
            b.font = .systemFont(ofSize: 12)
            b.controlSize = .small
            b.translatesAutoresizingMaskIntoConstraints = false
        }
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let footer = NSStackView(views: [clearBtn, loginCheckbox, pasteCheckbox, spacer, quitBtn])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false

        let contentViews: [NSView] = [header, hintField, searchField, scrollView, footer]
        for v in contentViews {
            v.translatesAutoresizingMaskIntoConstraints = false
            vfx.addSubview(v)
        }
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        pasteCheckbox.state = (UserDefaults.standard.object(forKey: kAutoPaste) == nil || UserDefaults.standard.bool(forKey: kAutoPaste)) ? .on : .off

        headerTopWithHint = header.topAnchor.constraint(equalTo: hintField.bottomAnchor, constant: 6)
        headerTopNoHint = header.topAnchor.constraint(equalTo: vfx.topAnchor, constant: 12)
        headerTopNoHint.isActive = true

        NSLayoutConstraint.activate([
            hintField.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 16),
            hintField.trailingAnchor.constraint(equalTo: vfx.trailingAnchor, constant: -16),
            hintField.topAnchor.constraint(equalTo: vfx.topAnchor, constant: 10),

            header.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 16),

            searchField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: vfx.trailingAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: vfx.trailingAnchor, constant: -14),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            footer.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: vfx.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: vfx.bottomAnchor, constant: -10),
            footer.heightAnchor.constraint(equalToConstant: 22),

            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])
    }

    func refresh() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        var items = history
        if !q.isEmpty {
            items = items.filter { $0.text.localizedCaseInsensitiveContains(q) }
        }
        let shown = Array(items.prefix(100))

        if shown.isEmpty {
            let l = NSTextField(labelWithString: q.isEmpty ? "还没有记录，去复制点东西吧" : "没有匹配的记录")
            l.font = .systemFont(ofSize: 12)
            l.textColor = .secondaryLabelColor
            stackView.addArrangedSubview(l)
            l.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 4).isActive = true
        } else {
            for it in shown {
                let card = ClipCardView(item: it,
                                        onCopy: { [weak self] item in self?.copyItem(item) },
                                        onPin: { [weak self] s in self?.togglePin(s) },
                                        onDelete: { [weak self] s in self?.deleteItem(s) })
                stackView.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            }
            if items.count > shown.count {
                let more = NSTextField(labelWithString: "…… 还有 \(items.count - shown.count) 条，用上面搜索框找更快")
                more.font = .systemFont(ofSize: 11)
                more.textColor = .tertiaryLabelColor
                stackView.addArrangedSubview(more)
                more.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 4).isActive = true
            }
        }
    }

    @objc func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        refresh()
        setHint(AXIsProcessTrusted() ? nil : "⚠️ 自动粘贴需要「辅助功能」权限，点本条提示去授权 —— 若列表里已有「剪贴板助手」，把开关关掉再重新打开一次")
        previousApp = NSWorkspace.shared.frontmostApplication
        if let w = statusItem.button?.window {
            let f = w.frame
            let x = max(8, f.maxX - 420)
            panel.setFrame(NSRect(x: x, y: f.minY - 6, width: 420, height: 584), display: false)
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()

        eventMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        })
        eventMonitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            guard let self else { return e }
            let pt = e.window?.convertPoint(toScreen: e.locationInWindow) ?? NSEvent.mouseLocation
            if self.panel.frame.contains(pt) {
                NSApp.activate(ignoringOtherApps: true)
                return e
            }
            if let b = self.statusItem.button, let w = b.window, w.frame.contains(pt) { return e }
            self.hidePanel()
            return e
        })
    }

    func hidePanel() {
        panel.orderOut(nil)
        for m in eventMonitors { NSEvent.removeMonitor(m) }
        eventMonitors.removeAll()
    }

    // MARK: 核心判断：这条复制是人干的吗？
    func isUserCopy() -> Bool {
        let key = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let left = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        let right = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
        return key < 1.0 || left < 1.0 || right < 1.0
    }

    // MARK: 从剪贴板抓取内容（文件 > 图片 > 文本）
    func readIncoming(_ pb: NSPasteboard) -> IncomingClip? {
        let types = pb.types ?? []
        // 1. 文件（Finder / 微信传文件等）
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let paths = urls.map { $0.path }
            return IncomingClip(text: "📄 " + paths.joined(separator: "\n"),
                                kind: "file", imageFile: nil, filePaths: paths)
        }
        // 2. 图片
        if types.contains(.png) || types.contains(.tiff) {
            var data = pb.data(forType: .png)
            if data == nil, let tiff = pb.data(forType: .tiff),
               let rep = NSBitmapImageRep(data: tiff) {
                data = rep.representation(using: .png, properties: [:])
            }
            guard let png = data, !png.isEmpty else { return nil }
            guard png.count <= maxImageBytes else {
                log("图片过大（\(png.count / 1_000_000)MB）跳过")
                return nil
            }
            let digest = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
            let name = String(digest.prefix(16))
            let url = imagesDir.appendingPathComponent(name + ".png")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? png.write(to: url)
            }
            return IncomingClip(text: "🖼 " + name, kind: "image", imageFile: url.path, filePaths: nil)
        }
        // 3. 文本
        if let t = pb.string(forType: .string), !t.isEmpty {
            return IncomingClip(text: t, kind: "text", imageFile: nil, filePaths: nil)
        }
        return nil
    }

    func tick() {
        pruneTemp()
        // 辅助功能权限监控：授权状态翻转时记录（授权生效/失效都能第一时间从日志确认）
        let nowT = CACurrentMediaTime()
        if nowT - lastAXCheckAt > 2.0 {
            lastAXCheckAt = nowT
            let ax = AXIsProcessTrusted()
            if ax != lastAXState {
                lastAXState = ax
                log(ax ? "✅ 辅助功能权限已生效（自动粘贴可用）" : "辅助功能权限已失效")
                if panel.isVisible { setHint(ax ? nil : "⚠️ 自动粘贴需要「辅助功能」权限，点本条提示去授权 —— 若列表里已有「剪贴板助手」，把开关关掉再重新打开一次") }
            }
        }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let clip = readIncoming(pb) else { return }
        let s = clip.text
        let now = Date()
        let userCopy = isUserCopy()
        defer {
            recentWrites.append((s, now))
            if recentWrites.count > 8 { recentWrites.removeFirst() }
        }

        // 还原模式检测：语音/工具类输入的指纹是 [旧内容A] → [语音B] → [把A写回来]
        // 不看键鼠动作——因为发语音消息按"发送"键也会产生键鼠动作，会把整个三连击豁免掉（实战教训）
        // 8 秒内"上上次写过的内容"再次出现 = 还原。人 8 秒内 A→B→A 复制的概率极低，可接受
        if recentWrites.count >= 2,
           let lastWrite = recentWrites.last,
           now.timeIntervalSince(lastWrite.time) < 8.0,
           recentWrites.dropLast().contains(where: { $0.text == s }) {
            // 拦截还在观察期的语音条目：根本不入库
            if let p = pending, p.clip.text != s {
                pending = nil; pendingTimer?.invalidate(); pendingTimer = nil
                log("还原模式[\(s.prefix(15))]：语音「\(p.clip.text.prefix(25))」已拦截，未入历史")
            }
            // 兜底：清掉夹在中间的那条（入库时间晚于语音写板时刻 = 就是语音 B，可能已被标永久）
            if let i = history.firstIndex(where: { $0.text != s && !$0.isPinned && $0.added >= lastWrite.time }) {
                let gone = history.remove(at: i)
                cleanupImageFiles([gone])
                log("还原模式：已清除「\(gone.text.prefix(25))」")
                save(); refreshIfVisible()
            } else {
                log("还原模式[\(s.prefix(15))]：无新增条目")
            }
            return
        }

        // 程序悄悄回写历史已有内容 → 跳过（人用 ⌘C 复制相同内容必有键鼠动作，不受影响）
        if !userCopy, history.contains(where: { $0.text == s && !$0.isPinned }) {
            log("程序回写[\(s.prefix(15))]：已在历史中，跳过")
            return
        }

        // 上一条还没定论的先提交（快速连续复制场景）
        commitPending()

        pending = (clip, now, userCopy)
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.commitPending()
        }
        log("观察期[\(userCopy ? "暂定永久" : "💬临时")][\(clip.kind)]：\(s.prefix(30).replacingOccurrences(of: "\n", with: " "))")
    }

    func commitPending() {
        guard let p = pending else { return }
        pending = nil
        pendingTimer?.invalidate(); pendingTimer = nil
        add(p.clip, isTemp: !p.userCopy)
        log("入库[\(p.userCopy ? "永久" : "💬临时")][\(p.clip.kind)]：\(p.clip.text.prefix(30).replacingOccurrences(of: "\n", with: " "))")
        refreshIfVisible()
    }

    // MARK: 增删改
    func add(_ clip: IncomingClip, isTemp: Bool) {
        history.removeAll { $0.text == clip.text && !$0.isPinned }
        let insertAt = history.firstIndex(where: { !$0.isPinned }) ?? history.count
        history.insert(ClipItem(text: clip.text, added: Date(), isTemp: isTemp,
                                kind: clip.kind, imageFile: clip.imageFile, filePaths: clip.filePaths),
                       at: insertAt)
        // 容量裁剪：超出就把最老的非置顶条目挤掉（图片条目顺带删盘上文件）
        while history.filter({ !$0.isPinned }).count > maxHistory,
              let last = history.lastIndex(where: { !$0.isPinned }) {
            let gone = history.remove(at: last)
            cleanupImageFiles([gone])
        }
        save()
    }

    // 删掉已无引用的图片文件
    func cleanupImageFiles(_ removed: [ClipItem]) {
        for it in removed where it.kind == "image" {
            guard let f = it.imageFile else { continue }
            if !history.contains(where: { $0.imageFile == f }) {
                try? FileManager.default.removeItem(atPath: f)
            }
        }
    }

    func pruneTemp() {
        let now = Date()
        let expired = history.filter { $0.isTemp && !$0.isPinned && now.timeIntervalSince($0.added) > tempLifetime }
        guard !expired.isEmpty else { return }
        let expiredKeys = Set(expired.map { $0.text })
        history.removeAll { expiredKeys.contains($0.text) }
        cleanupImageFiles(expired)
        save(); refreshIfVisible()
    }

    func refreshIfVisible() {
        if panel.isVisible { refresh() }
    }

    func loadStore() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: kHistoryV3),
           let items = try? JSONDecoder().decode([ClipItem].self, from: data) {
            history = items
            return
        }
        // v2 迁移：旧置顶数组合并进 isPinned 字段
        if let data = d.data(forKey: kHistoryV2),
           var items = try? JSONDecoder().decode([ClipItem].self, from: data) {
            let pinnedSet = Set(d.stringArray(forKey: kPinnedV2) ?? [])
            for i in items.indices { items[i].isPinned = pinnedSet.contains(items[i].text) }
            history = items.filter { $0.isPinned } + items.filter { !$0.isPinned }
            save()
            log("已从 v2 迁移 \(items.count) 条记录（含置顶 \(history.filter { $0.isPinned }.count) 条）")
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: kHistoryV3)
        }
    }

    // MARK: 卡片动作
    func copyItem(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case "image":
            guard let f = item.imageFile,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: f)), !data.isEmpty else {
                log("图片缓存缺失：\(item.imageFile ?? "?")，放弃复制")
                setHint("⚠️ 这张图片的缓存已被清理，无法再粘贴（可在设置里重新复制一次原图）")
                return
            }
            pb.setData(data, forType: .png)
            // 同时写 TIFF：部分应用（微信等）只认老式 TIFF 图片类型，只写 PNG 会贴不出来
            if let rep = NSBitmapImageRep(data: data), let tiff = rep.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        case "file":
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty {
                pb.writeObjects(urls)
            } else {
                pb.setString(item.text, forType: .string)
            }
        default:
            pb.setString(item.text, forType: .string)
        }
        lastChangeCount = pb.changeCount
        // 刚用过的条目挪到非置顶区最前（Windows 行为），并转永久
        if let i = history.firstIndex(where: { $0.text == item.text }) {
            history[i].isTemp = false
            let it = history.remove(at: i)
            let pos = history.firstIndex(where: { !$0.isPinned }) ?? history.count
            history.insert(it, at: pos)
            save()
        }

        let wantPaste = UserDefaults.standard.object(forKey: kAutoPaste) == nil || UserDefaults.standard.bool(forKey: kAutoPaste)
        hidePanel()
        guard wantPaste else { return }

        guard AXIsProcessTrusted() else {
            // 不再静默失败：面板会常驻授权提示，同时弹一次系统引导
            setHint("⚠️ 自动粘贴需要「辅助功能」权限，点本条提示去授权 —— 若列表里已有「剪贴板助手」，把开关关掉再重新打开一次（重新编译后旧授权会失效）")
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            log("自动粘贴缺辅助功能权限：已显示提示 + 弹系统引导")
            return
        }

        // 面板是非激活面板，前台应用没变、光标还停在原输入框里，稍等布局收尾后模拟 ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            if let prev = self?.previousApp, prev != NSWorkspace.shared.frontmostApplication {
                prev.activate(options: [.activateIgnoringOtherApps])
                usleep(120000)
            }
            Self.sendPasteKeystroke()
            self?.log("自动粘贴：已模拟 ⌘V（\(item.kind)）→ \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        }
    }

    static func sendPasteKeystroke() {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),   // V
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else { return }
        down.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(25000)
        up.flags = .maskCommand
        up.post(tap: .cghidEventTap)
    }

    func togglePin(_ s: String) {
        guard let i = history.firstIndex(where: { $0.text == s }) else { return }
        history[i].isPinned.toggle()
        let it = history.remove(at: i)
        if it.isPinned {
            history.insert(it, at: 0)
        } else {
            let pos = history.firstIndex(where: { !$0.isPinned }) ?? history.count
            history.insert(it, at: pos)
        }
        save(); refresh()
    }

    func deleteItem(_ s: String) {
        let removed = history.filter { $0.text == s }
        history.removeAll { $0.text == s }
        cleanupImageFiles(removed)
        save(); refresh()
    }

    // MARK: 底栏动作
    @objc func clearAll() {
        let removed = history.filter { !$0.isPinned }
        history.removeAll { !$0.isPinned }
        cleanupImageFiles(removed)
        save(); refresh()
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func toggleAutoPaste() {
        UserDefaults.standard.set(pasteCheckbox.state == .on, forKey: kAutoPaste)
        log("自动粘贴开关 → \(pasteCheckbox.state == .on ? "开" : "关")")
    }

    // MARK: 顶部提示条
    func setHint(_ msg: String?) {
        guard let msg, !msg.isEmpty else {
            hintField.isHidden = true
            headerTopWithHint.isActive = false
            headerTopNoHint.isActive = true
            return
        }
        hintField.stringValue = msg
        hintField.isHidden = false
        headerTopNoHint.isActive = false
        headerTopWithHint.isActive = true
        // 约束变化后让面板高度自适应提示条（高度锁了 560，只调内容起点即可）
        panel.contentView?.needsLayout = true
    }

    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        log("已打开系统设置·辅助功能面板")
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    // MARK: 搜索
    func controlTextDidChange(_ obj: Notification) { refresh() }
}

let gDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = gDelegate
app.setActivationPolicy(.accessory)
app.run()
