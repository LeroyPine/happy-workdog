import AppKit
import Combine
import SwiftUI

@MainActor
final class WorkdogAppDelegate: NSObject, NSApplicationDelegate {
    private let store = WorkdogStore()
    private let reminderCoordinator = ReminderCoordinator()
    private let clipboardCoordinator = ClipboardCoordinator()
    private let screenshotCoordinator = ScreenshotCoordinator()
    private let hotkeyCoordinator = HotkeyCoordinator()
    private let defaults = UserDefaults.standard
    private var petWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var clipboardWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var petWindowLayoutCancellables: Set<AnyCancellable> = []
    private var shouldRestorePetWindowAfterScreenshot = false

    private enum WindowKey {
        static let petOriginX = "workdog.petWindow.originX"
        static let petOriginY = "workdog.petWindow.originY"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplicationIcon()
        configureMainMenu()
        reminderCoordinator.onReminder = { [weak self] kind in
            self?.handleReminder(kind, shouldActivate: false)
        }
        reminderCoordinator.onScheduleChanged = { [weak self] in
            self?.store.noteReminderScheduleChanged()
        }
        store.onPomodoroCompleted = { [weak self] mode, message in
            self?.handlePomodoroCompletion(mode: mode, message: message)
        }
        clipboardCoordinator.onTextChanged = { [weak self] text in
            self?.store.recordClipboardText(text)
        }
        clipboardCoordinator.onImageChanged = { [weak self] image in
            self?.store.recordClipboardImage(image)
        }
        clipboardCoordinator.onFileURLsChanged = { [weak self] urls in
            self?.store.recordClipboardFiles(urls)
        }
        screenshotCoordinator.onStarted = { [weak self] in
            self?.store.showStatusMessage("框选需要截图的区域，按 ESC 可以取消。", mood: .energized)
        }
        screenshotCoordinator.onCompleted = { [weak self] result in
            self?.handleScreenshotCompletion(result)
        }
        hotkeyCoordinator.onHotkeyPressed = { [weak self] action in
            self?.handleHotkey(action)
        }

        setupStatusItem()
        buildPetWindow()
        reminderCoordinator.requestNotificationPermission()
        clipboardCoordinator.start()
        showPetWindow(activate: true)
        reminderCoordinator.reschedule(using: store)
        hotkeyCoordinator.reschedule(using: store)
        store.updateFailedHotkeyActions(hotkeyCoordinator.failedActions)
    }

    private func configureApplicationIcon() {
        guard let icon = Self.loadApplicationIcon() else { return }
        NSApp.applicationIconImage = icon
    }

    private static func loadApplicationIcon() -> NSImage? {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidateURLs = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns"),
            currentDirectory.appendingPathComponent("assets/AppIcon.icns"),
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            guard FileManager.default.fileExists(atPath: url.path),
                  let icon = NSImage(contentsOf: url),
                  icon.isValid
            else {
                continue
            }
            return icon
        }

        return nil
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "设置...", action: #selector(showSettingsWindow(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出快乐小狗", action: #selector(quitApp(_:)), keyEquivalent: "q")
        for item in appMenu.items {
            item.target = self
        }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "快乐小狗")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "快乐小狗"
        item.menu = buildMenu()
        statusItem = item
    }

    private func refreshStatusMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "快乐小狗")
        menu.autoenablesItems = false

        let visibleTitle = isPetVisible ? "隐藏小狗" : "显示小狗"
        menu.addItem(withTitle: visibleTitle, action: #selector(togglePetWindow(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "打开设置", action: #selector(showSettingsWindow(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        let reminderTitle = store.remindersEnabled ? "暂停提醒" : "恢复提醒"
        menu.addItem(withTitle: reminderTitle, action: #selector(toggleReminders(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "喝水一下", action: #selector(triggerWaterReminder(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "休息一下", action: #selector(triggerRestReminder(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "打气一下", action: #selector(triggerCheerReminder(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "区域截图到剪贴板", action: #selector(takeScreenshot(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let favoritesMenuItem = NSMenuItem(title: "常用入口", action: nil, keyEquivalent: "")
        favoritesMenuItem.submenu = buildFavoritesMenu()
        menu.addItem(favoritesMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "番茄钟 \(store.pomodoroTimeText)", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: store.pomodoroPrimaryActionTitle, action: #selector(togglePomodoro(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "重置番茄钟", action: #selector(resetPomodoro(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪贴板历史", action: #selector(showClipboardWindow(_:)), keyEquivalent: "")
        let clipboardTitle = store.clipboardHistoryEnabled ? "暂停剪贴板记录" : "恢复剪贴板记录"
        menu.addItem(withTitle: clipboardTitle, action: #selector(toggleClipboardHistory(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quitApp(_:)), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        return menu
    }

    private var isPetVisible: Bool {
        petWindowController?.window?.isVisible ?? false
    }

    private func buildPetWindow() {
        let window = WorkdogWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PetWindowLayout.width,
                height: PetWindowLayout.compactHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let rootView = PetRootView(
            store: store,
            onOpenSettings: { [weak self] in
                self?.showSettingsWindow(nil)
            },
            onOpenClipboard: { [weak self] in
                self?.showClipboardWindow(nil)
            },
            onTakeScreenshot: { [weak self] in
                self?.takeScreenshot(nil)
            },
            onOpenFavoriteEntry: { [weak self] entry in
                self?.openFavoriteEntry(entry)
            },
            onRecordAction: { [weak self] kind in
                self?.handleManualRecord(kind)
            }
        )
        window.contentView = WorkdogPetHostingView(rootView: rootView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isPomodoroPanelPresented = { [weak store] in
            store?.isPomodoroPanelPresented ?? false
        }
        window.onFrameMoved = { [weak self, weak window] in
            guard let window else { return }
            self?.savePetWindowOrigin(window)
        }
        window.orderOut(nil)

        petWindowController = NSWindowController(window: window)
        observePetWindowLayout()
    }

    private func observePetWindowLayout() {
        petWindowLayoutCancellables.removeAll()

        store.$isPomodoroPanelPresented
            .combineLatest(store.$isFavoritesPanelPresented)
            .receive(on: RunLoop.main)
            .sink { [weak self] isPomodoroPresented, isFavoritesPresented in
                self?.resizePetWindowForContent(isPanelPresented: isPomodoroPresented || isFavoritesPresented)
            }
            .store(in: &petWindowLayoutCancellables)
    }

    private func resizePetWindowForContent(isPanelPresented: Bool) {
        guard let window = petWindowController?.window as? WorkdogWindow else { return }
        window.setPetContentHeight(PetWindowLayout.height(isPanelPresented: isPanelPresented))
    }

    private func showPetWindow(activate: Bool) {
        guard let window = petWindowController?.window else { return }
        placePetWindowIfNeeded(window, force: !window.isVisible)
        if activate {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        window.orderFrontRegardless()
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        refreshStatusMenu()
    }

    private func hidePetWindow() {
        petWindowController?.window?.orderOut(nil)
        refreshStatusMenu()
    }

    private func handleReminder(_ kind: ReminderKind, shouldActivate: Bool) {
        store.triggerReminder(kind)
        reminderCoordinator.writeReminderLog(kind: kind, message: store.currentMessage)
        reminderCoordinator.sendNotification(kind: kind, message: store.currentMessage)
        if !screenshotCoordinator.isCapturing,
           store.revealWindowOnReminder || !isPetVisible {
            showPetWindow(activate: shouldActivate)
        }
    }

    private func handleManualRecord(_ kind: ReminderKind) {
        store.recordManualAction(kind)
        reminderCoordinator.reset(kind: kind, using: store)
        reminderCoordinator.writeLog(category: "record-\(kind.rawValue)", message: store.currentMessage)
        if !isPetVisible {
            showPetWindow(activate: false)
        }
    }

    private func handlePomodoroCompletion(mode: PomodoroMode, message: String) {
        reminderCoordinator.writeLog(category: "pomodoro-\(mode.rawValue)", message: message)
        reminderCoordinator.sendNotification(
            title: "\(mode.title)结束",
            message: message,
            identifierPrefix: "happy-workdog-pomodoro"
        )
        if !screenshotCoordinator.isCapturing,
           store.revealWindowOnReminder || !isPetVisible {
            showPetWindow(activate: false)
        }
        refreshStatusMenu()
    }

    private func handleScreenshotCompletion(_ result: ScreenshotCoordinator.CaptureResult) {
        switch result {
        case .captured:
            store.showStatusMessage("截图已复制到剪贴板。", mood: .proud)
        case .cancelled:
            store.showStatusMessage("已取消截图。", mood: .idle)
        case .permissionRequired:
            store.showStatusMessage("需要允许系统屏幕录制权限后才能截图，正在打开系统设置。", mood: .idle)
            openScreenRecordingPreferences()
        case .failed:
            store.showStatusMessage("没能启动区域截图。", mood: .idle)
        }

        if shouldRestorePetWindowAfterScreenshot {
            showPetWindow(activate: false)
        }
        shouldRestorePetWindowAfterScreenshot = false
    }

    private func placePetWindowIfNeeded(_ window: NSWindow, force: Bool = false) {
        let margin: CGFloat = 28
        let visibleFrames = visibleScreenFrames(insetBy: margin)
        let isVisibleOnAnyScreen = visibleFrames.contains { $0.intersects(window.frame) }

        guard force || !isVisibleOnAnyScreen else { return }

        if let savedOrigin = savedPetWindowOrigin(for: window),
           visibleFrames.contains(where: { $0.intersects(frame(for: window, at: savedOrigin)) }) {
            window.setFrameOrigin(savedOrigin)
            return
        }

        let screenFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.maxX - window.frame.width - margin
        let y = screenFrame.minY + margin
        window.setFrameOrigin(NSPoint(x: max(screenFrame.minX + margin, x), y: y))
    }

    private func visibleScreenFrames(insetBy margin: CGFloat) -> [NSRect] {
        let frames = NSScreen.screens.map { $0.visibleFrame.insetBy(dx: margin, dy: margin) }
        if frames.isEmpty {
            return [NSRect(x: 0, y: 0, width: 1440, height: 900).insetBy(dx: margin, dy: margin)]
        }
        return frames
    }

    private func savedPetWindowOrigin(for window: NSWindow) -> NSPoint? {
        guard defaults.object(forKey: WindowKey.petOriginX) != nil,
              defaults.object(forKey: WindowKey.petOriginY) != nil
        else { return nil }

        return NSPoint(
            x: defaults.double(forKey: WindowKey.petOriginX),
            y: defaults.double(forKey: WindowKey.petOriginY)
        )
    }

    private func savePetWindowOrigin(_ window: NSWindow) {
        defaults.set(window.frame.origin.x, forKey: WindowKey.petOriginX)
        defaults.set(window.frame.origin.y, forKey: WindowKey.petOriginY)
    }

    private func frame(for window: NSWindow, at origin: NSPoint) -> NSRect {
        NSRect(origin: origin, size: window.frame.size)
    }

    @objc private func showSettingsWindow(_ sender: Any?) {
        if settingsWindowController == nil {
            let rootView = SettingsView(
                store: store,
                nextReminderDate: { [weak self] kind in
                    self?.reminderCoordinator.nextFireDate(for: kind)
                },
                onSettingsChanged: { [weak self] scope in
                    guard let self else { return }
                    switch scope {
                    case .reminderSchedule:
                        self.reminderCoordinator.reschedule(using: self.store)
                    case .hotkeys:
                        self.hotkeyCoordinator.reschedule(using: self.store)
                        self.store.updateFailedHotkeyActions(self.hotkeyCoordinator.failedActions)
                    case .statusMenu:
                        break
                    case .all:
                        self.reminderCoordinator.reschedule(using: self.store)
                        self.hotkeyCoordinator.reschedule(using: self.store)
                        self.store.updateFailedHotkeyActions(self.hotkeyCoordinator.failedActions)
                    }
                    self.refreshStatusMenu()
                },
                onOpenClipboard: { [weak self] in
                    self?.showClipboardWindow(nil)
                }
            )
            let hosting = NSHostingController(rootView: rootView)
            let frame = settingsWindowInitialFrame()
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.minSize = NSSize(width: 960, height: 700)
            window.title = "快乐小狗设置"
            window.isReleasedWhenClosed = false

            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func settingsWindowInitialFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1180, max(1040, visibleFrame.width * 0.82))
        let height = min(820, max(720, visibleFrame.height * 0.88))
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    @objc private func showClipboardWindow(_ sender: Any?) {
        if clipboardWindowController == nil {
            let rootView = ClipboardHistoryView(
                store: store,
                onSelect: { [weak self] item in
                    self?.copyClipboardHistoryItem(item)
                },
                onStateChanged: { [weak self] in
                    self?.refreshStatusMenu()
                }
            )
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.minSize = NSSize(width: 480, height: 560)
            window.title = "剪贴板历史"
            window.isReleasedWhenClosed = false
            window.center()

            clipboardWindowController = NSWindowController(window: window)
        }

        clipboardWindowController?.showWindow(nil)
        clipboardWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func copyClipboardHistoryItem(_ item: ClipboardHistoryItem) {
        switch item.kind {
        case .text:
            guard let text = item.text else { return }
            clipboardCoordinator.copyTextToPasteboard(text)
        case .image:
            guard let image = store.image(for: item) else { return }
            clipboardCoordinator.copyImageToPasteboard(image)
        case .file:
            let urls = store.fileURLs(for: item)
            guard !urls.isEmpty else { return }
            clipboardCoordinator.copyFileURLsToPasteboard(urls)
        }
    }

    private func buildFavoritesMenu() -> NSMenu {
        let menu = NSMenu(title: "常用入口")
        menu.autoenablesItems = false

        if store.favoriteEntries.isEmpty {
            let item = menu.addItem(withTitle: "添加入口...", action: #selector(showSettingsWindow(_:)), keyEquivalent: "")
            item.target = self
            return menu
        }

        appendFavoriteNodes(store.favoriteRootNodes, to: menu)

        return menu
    }

    private func openFavoriteEntry(_ entry: FavoriteEntry) {
        guard !entry.isFolder else { return }
        let cleanTarget = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else { return }

        switch entry.kind {
        case .link, .website:
            var target = cleanTarget
            if !target.contains("://"), !target.hasPrefix("/") && !target.hasPrefix("~") {
                target = "https://\(target)"
            }
            if target.hasPrefix("/") || target.hasPrefix("~") {
                let url = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
                NSWorkspace.shared.open(url)
            } else if let url = URL(string: target) {
                NSWorkspace.shared.open(url)
            }
        case .file:
            let url = URL(fileURLWithPath: (cleanTarget as NSString).expandingTildeInPath)
            NSWorkspace.shared.open(url)
        case .folder:
            return
        }
    }

    private func appendFavoriteNodes(_ nodes: [FavoriteTreeNode], to menu: NSMenu) {
        for node in nodes {
            if node.entry.isFolder {
                let folderItem = NSMenuItem(title: node.entry.alias, action: nil, keyEquivalent: "")
                folderItem.image = NSImage(systemSymbolName: node.entry.kind.symbol, accessibilityDescription: node.entry.kind.title)
                let submenu = NSMenu(title: node.entry.alias)
                appendFavoriteNodes(node.children, to: submenu)
                folderItem.submenu = submenu
                menu.addItem(folderItem)
            } else {
                let item = FavoriteMenuItem(entry: node.entry)
                item.target = self
                item.action = #selector(openFavoriteMenuItem(_:))
                menu.addItem(item)
            }
        }
    }

    @objc private func togglePetWindow(_ sender: Any?) {
        if isPetVisible {
            hidePetWindow()
        } else {
            showPetWindow(activate: true)
        }
    }

    @objc private func toggleReminders(_ sender: Any?) {
        store.remindersEnabled.toggle()
        reminderCoordinator.reschedule(using: store)
        refreshStatusMenu()
    }

    @objc private func triggerWaterReminder(_ sender: Any?) {
        handleManualRecord(.water)
    }

    @objc private func triggerRestReminder(_ sender: Any?) {
        handleManualRecord(.rest)
    }

    @objc private func triggerCheerReminder(_ sender: Any?) {
        handleManualRecord(.cheer)
    }

    @objc private func takeScreenshot(_ sender: Any?) {
        guard !screenshotCoordinator.isCapturing else { return }
        guard screenshotCoordinator.requestScreenCapturePermissionIfNeeded() else {
            handleScreenshotCompletion(.permissionRequired)
            return
        }

        shouldRestorePetWindowAfterScreenshot = isPetVisible
        if shouldRestorePetWindowAfterScreenshot {
            hidePetWindow()
        }
        screenshotCoordinator.captureSelectionToClipboard(after: 0.16)
    }

    private func openScreenRecordingPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }

    @objc private func togglePomodoro(_ sender: Any?) {
        store.togglePomodoro()
        refreshStatusMenu()
    }

    @objc private func resetPomodoro(_ sender: Any?) {
        store.resetPomodoro()
        refreshStatusMenu()
    }

    @objc private func toggleClipboardHistory(_ sender: Any?) {
        store.clipboardHistoryEnabled.toggle()
        refreshStatusMenu()
    }

    @objc private func openFavoriteMenuItem(_ sender: FavoriteMenuItem) {
        openFavoriteEntry(sender.entry)
    }

    private func handleHotkey(_ action: HotkeyAction) {
        switch action {
        case .clipboardHistory:
            showClipboardWindow(nil)
        case .screenshot:
            takeScreenshot(nil)
        case .pomodoroToggle:
            togglePomodoro(nil)
        case .togglePetWindow:
            togglePetWindow(nil)
        case .favorites:
            store.isPomodoroPanelPresented = false
            store.isFavoritesPanelPresented = true
            showPetWindow(activate: true)
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        clipboardCoordinator.stop()
        hotkeyCoordinator.stop()
        NSApp.terminate(nil)
    }
}

final class WorkdogWindow: NSWindow {
    var onFrameMoved: (() -> Void)?
    var isPomodoroPanelPresented: (() -> Bool)?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if shouldBeginPetDrag(at: event.locationInWindow) {
                dragStartMouseLocation = NSEvent.mouseLocation
                dragStartWindowOrigin = frame.origin
            } else {
                clearPetDrag()
            }
            super.sendEvent(event)

        case .leftMouseDragged:
            if let dragStartMouseLocation, let dragStartWindowOrigin {
                let mouseLocation = NSEvent.mouseLocation
                let nextOrigin = NSPoint(
                    x: dragStartWindowOrigin.x + mouseLocation.x - dragStartMouseLocation.x,
                    y: dragStartWindowOrigin.y + mouseLocation.y - dragStartMouseLocation.y
                )
                setFrameOrigin(nextOrigin)
                onFrameMoved?()
                return
            }
            super.sendEvent(event)

        case .leftMouseUp:
            clearPetDrag()
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    func setPetContentHeight(_ height: CGFloat) {
        let normalizedHeight = max(PetWindowLayout.compactHeight, height)
        guard abs(frame.height - normalizedHeight) > 0.5 else { return }

        let topY = frame.maxY
        var nextFrame = NSRect(
            x: frame.minX,
            y: topY - normalizedHeight,
            width: PetWindowLayout.width,
            height: normalizedHeight
        )

        if let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let margin: CGFloat = 8
            if nextFrame.minY < visibleFrame.minY + margin {
                nextFrame.origin.y = visibleFrame.minY + margin
            }
            if nextFrame.maxY > visibleFrame.maxY - margin {
                nextFrame.origin.y = visibleFrame.maxY - margin - normalizedHeight
            }
        }

        setFrame(nextFrame, display: true, animate: true)
    }

    @objc private func frameDidMove(_ notification: Notification) {
        onFrameMoved?()
    }

    private func clearPetDrag() {
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
    }

    private func shouldBeginPetDrag(at point: NSPoint) -> Bool {
        guard isPomodoroPanelPresented?() != true else { return false }
        return petDragRects.contains { $0.contains(point) }
    }

    private var petDragRects: [NSRect] {
        [
            rectFromTop(
                x: PetWindowLayout.avatarDragX,
                y: PetWindowLayout.avatarDragYFromTop,
                width: PetWindowLayout.avatarSize,
                height: PetWindowLayout.avatarSize
            ),
        ]
    }

    private func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        let heightFromTop = contentView?.bounds.height ?? frame.height
        return NSRect(x: x, y: heightFromTop - y - height, width: width, height: height)
    }
}

final class WorkdogPetHostingView: NSHostingView<PetRootView> {
    required init(rootView: PetRootView) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class FavoriteMenuItem: NSMenuItem {
    let entry: FavoriteEntry

    init(entry: FavoriteEntry) {
        self.entry = entry
        super.init(title: entry.alias, action: nil, keyEquivalent: "")
        image = NSImage(systemSymbolName: entry.kind.symbol, accessibilityDescription: entry.kind.title)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
