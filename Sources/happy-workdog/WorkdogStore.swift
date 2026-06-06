import AppKit
import CryptoKit
import Foundation
import SwiftUI

@MainActor
final class WorkdogStore: ObservableObject {
    @Published var dogName: String { didSet { persist() } }
    @Published var bodyShape: DogShape { didSet { persist() } }
    @Published var coat: DogCoat { didSet { persist() } }
    @Published var avatarScale: Double { didSet { persist() } }
    @Published var remindersEnabled: Bool { didSet { persist() } }
    @Published var waterEnabled: Bool { didSet { persist() } }
    @Published var restEnabled: Bool { didSet { persist() } }
    @Published var cheerEnabled: Bool { didSet { persist() } }
    @Published var waterIntervalMinutes: Double { didSet { persist() } }
    @Published var restIntervalMinutes: Double { didSet { persist() } }
    @Published var cheerIntervalMinutes: Double { didSet { persist() } }
    @Published private(set) var reminderPreset: ReminderPreset
    @Published var revealWindowOnReminder: Bool { didSet { persist() } }
    @Published var pomodoroFocusMinutes: Double { didSet { persist(); syncIdlePomodoroDuration(for: .focus) } }
    @Published var pomodoroShortBreakMinutes: Double { didSet { persist(); syncIdlePomodoroDuration(for: .shortBreak) } }
    @Published var pomodoroLongBreakMinutes: Double { didSet { persist(); syncIdlePomodoroDuration(for: .longBreak) } }
    @Published var pomodoroLongBreakEvery: Int { didSet { persist() } }
    @Published private(set) var pomodoroMode: PomodoroMode
    @Published private(set) var pomodoroState: PomodoroState
    @Published private(set) var pomodoroRemainingSeconds: Int
    @Published private(set) var completedFocusCount: Int
    @Published var isPomodoroPanelPresented: Bool
    @Published var isFavoritesPanelPresented: Bool
    @Published var currentMessage: String
    @Published var currentReminder: ReminderKind
    @Published var currentMood: DogMood
    @Published var phrasePack: WorkdogPhrasePack { didSet { persist() } }
    @Published var reminderPulse: Int
    @Published var pettingPulse: Int
    @Published private(set) var todayDateKey: String
    @Published private(set) var todayFocusCount: Int
    @Published private(set) var todayWaterRecords: Int
    @Published private(set) var todayRestRecords: Int
    @Published private(set) var todayCheerRecords: Int
    @Published private(set) var todayWaterReminders: Int
    @Published private(set) var todayRestReminders: Int
    @Published private(set) var todayCheerReminders: Int
    @Published private(set) var todayActivityEvents: [WorkdogActivityEvent]
    @Published private(set) var todayPetTouches: Int
    @Published var clipboardHistoryEnabled: Bool { didSet { persist() } }
    @Published var clipboardMaxHistoryCount: Int { didSet { trimClipboardHistory(); persist() } }
    @Published var clipboardRecordTextEnabled: Bool { didSet { persist() } }
    @Published var clipboardRecordImageEnabled: Bool { didSet { persist() } }
    @Published var clipboardRecordFileEnabled: Bool { didSet { persist() } }
    @Published var clipboardSensitiveFilteringEnabled: Bool { didSet { persist() } }
    @Published var clipboardSensitiveKeywordsText: String { didSet { persist() } }
    @Published var clipboardSensitiveTokenHeuristicEnabled: Bool { didSet { persist() } }
    @Published private(set) var clipboardHistory: [ClipboardHistoryItem]
    @Published private(set) var favoriteEntries: [FavoriteEntry]
    @Published private(set) var pinnedQuickActions: [QuickAction]
    @Published var hotkeysEnabled: Bool { didSet { persist() } }
    @Published private(set) var hotkeys: [HotkeyAction: WorkdogHotkey?]
    @Published private(set) var failedHotkeyActions: Set<HotkeyAction>
    @Published private(set) var reminderScheduleRevision: Int

    var onPomodoroCompleted: ((PomodoroMode, String) -> Void)?

    private let defaults = UserDefaults.standard
    private var didMigrateFavoriteEntries = false
    private var resetMoodWorkItem: DispatchWorkItem?
    private var pomodoroTimer: Timer?
    private let clipboardImagesDirectory: URL

    private struct PreparedClipboardImage: Sendable {
        let filename: String
        let pixelWidth: Int
        let pixelHeight: Int
        let contentHash: String
        let copiedAt: Date
    }

    private struct ClipboardPinState {
        let isPinned: Bool
        let pinnedAt: Date?
    }

    private enum Key {
        static let dogName = "workdog.dogName"
        static let bodyShape = "workdog.bodyShape"
        static let coat = "workdog.coat"
        static let avatarScale = "workdog.avatarScale"
        static let remindersEnabled = "workdog.remindersEnabled"
        static let waterEnabled = "workdog.waterEnabled"
        static let restEnabled = "workdog.restEnabled"
        static let cheerEnabled = "workdog.cheerEnabled"
        static let waterIntervalMinutes = "workdog.waterIntervalMinutes"
        static let restIntervalMinutes = "workdog.restIntervalMinutes"
        static let cheerIntervalMinutes = "workdog.cheerIntervalMinutes"
        static let reminderPreset = "workdog.reminderPreset"
        static let revealWindowOnReminder = "workdog.revealWindowOnReminder"
        static let pomodoroFocusMinutes = "workdog.pomodoroFocusMinutes"
        static let pomodoroShortBreakMinutes = "workdog.pomodoroShortBreakMinutes"
        static let pomodoroLongBreakMinutes = "workdog.pomodoroLongBreakMinutes"
        static let pomodoroLongBreakEvery = "workdog.pomodoroLongBreakEvery"
        static let pomodoroMode = "workdog.pomodoroMode"
        static let completedFocusCount = "workdog.completedFocusCount"
        static let todayDateKey = "workdog.today.dateKey"
        static let todayFocusCount = "workdog.today.focusCount"
        static let todayWaterRecords = "workdog.today.waterRecords"
        static let todayRestRecords = "workdog.today.restRecords"
        static let todayCheerRecords = "workdog.today.cheerRecords"
        static let todayWaterReminders = "workdog.today.waterReminders"
        static let todayRestReminders = "workdog.today.restReminders"
        static let todayCheerReminders = "workdog.today.cheerReminders"
        static let todayActivityEvents = "workdog.today.activityEvents"
        static let todayPetTouches = "workdog.today.petTouches"
        static let clipboardHistoryEnabled = "workdog.clipboard.enabled"
        static let clipboardMaxHistoryCount = "workdog.clipboard.maxHistoryCount"
        static let clipboardRecordTextEnabled = "workdog.clipboard.recordTextEnabled"
        static let clipboardRecordImageEnabled = "workdog.clipboard.recordImageEnabled"
        static let clipboardRecordFileEnabled = "workdog.clipboard.recordFileEnabled"
        static let clipboardSensitiveFilteringEnabled = "workdog.clipboard.sensitiveFilteringEnabled"
        static let clipboardSensitiveKeywordsText = "workdog.clipboard.sensitiveKeywordsText"
        static let clipboardSensitiveTokenHeuristicEnabled = "workdog.clipboard.sensitiveTokenHeuristicEnabled"
        static let clipboardHistory = "workdog.clipboard.history"
        static let favoriteEntries = "workdog.favorites.entries"
        static let pinnedQuickActions = "workdog.quickActions.pinned"
        static let hotkeysEnabled = "workdog.hotkeys.enabled"
        static let hotkeys = "workdog.hotkeys.bindings"
        static let phrasePack = "workdog.phrasePack"
    }

    static let clipboardHistoryCountOptions = [10, 20, 50, 100, 200]
    static let defaultClipboardHistoryCount = 20
    nonisolated static let defaultClipboardSensitiveKeywords = ["password", "passwd", "token", "secret", "apikey", "api_key", "bearer", "authorization"]
    nonisolated static let defaultClipboardSensitiveKeywordsText = defaultClipboardSensitiveKeywords.joined(separator: "\n")
    static let defaultAvatarScale = 0.85
    static let maximumAvatarScale = 0.95
    static let avatarScaleRange = defaultAvatarScale...maximumAvatarScale

    var avatarDisplayScale: Double {
        Self.displayAvatarScale(for: avatarScale)
    }

    var clipboardSensitiveKeywords: [String] {
        Self.parseClipboardSensitiveKeywords(clipboardSensitiveKeywordsText)
    }

    static func normalizedAvatarScale(_ scale: Double) -> Double {
        min(max(scale, avatarScaleRange.lowerBound), avatarScaleRange.upperBound)
    }

    static func displayAvatarScale(for actualScale: Double) -> Double {
        1.0 + normalizedAvatarScale(actualScale) - defaultAvatarScale
    }

    init() {
        let initialClipboardImagesDirectory = Self.makeClipboardImagesDirectory()
        clipboardImagesDirectory = initialClipboardImagesDirectory
        let initialDogName = defaults.string(forKey: Key.dogName) ?? "快乐小狗"
        let initialPomodoroMode = PomodoroMode(rawValue: defaults.string(forKey: Key.pomodoroMode) ?? "") ?? .focus
        let initialFocusMinutes = defaults.object(forKey: Key.pomodoroFocusMinutes) as? Double ?? PomodoroMode.focus.defaultMinutes
        let initialShortBreakMinutes = defaults.object(forKey: Key.pomodoroShortBreakMinutes) as? Double ?? PomodoroMode.shortBreak.defaultMinutes
        let initialLongBreakMinutes = defaults.object(forKey: Key.pomodoroLongBreakMinutes) as? Double ?? PomodoroMode.longBreak.defaultMinutes
        let initialWaterInterval = defaults.object(forKey: Key.waterIntervalMinutes) as? Double ?? 45
        let initialRestInterval = defaults.object(forKey: Key.restIntervalMinutes) as? Double ?? 90
        let initialCheerInterval = defaults.object(forKey: Key.cheerIntervalMinutes) as? Double ?? 120
        let initialClipboardMaxHistoryCount = Self.normalizedClipboardHistoryCount(
            defaults.object(forKey: Key.clipboardMaxHistoryCount) as? Int ?? Self.defaultClipboardHistoryCount
        )
        let initialPhrasePack = Self.loadPhrasePack(from: defaults, key: Key.phrasePack)
        let currentTodayKey = Self.todayKey()
        let savedTodayKey = defaults.string(forKey: Key.todayDateKey)
        let shouldKeepTodayStats = savedTodayKey == currentTodayKey
        dogName = initialDogName
        bodyShape = DogShape(rawValue: defaults.string(forKey: Key.bodyShape) ?? "") ?? .round
        coat = DogCoat(rawValue: defaults.string(forKey: Key.coat) ?? "") ?? .golden
        avatarScale = Self.normalizedAvatarScale(defaults.object(forKey: Key.avatarScale) as? Double ?? Self.defaultAvatarScale)
        remindersEnabled = defaults.object(forKey: Key.remindersEnabled) as? Bool ?? true
        waterEnabled = defaults.object(forKey: Key.waterEnabled) as? Bool ?? true
        restEnabled = defaults.object(forKey: Key.restEnabled) as? Bool ?? true
        cheerEnabled = defaults.object(forKey: Key.cheerEnabled) as? Bool ?? true
        waterIntervalMinutes = initialWaterInterval
        restIntervalMinutes = initialRestInterval
        cheerIntervalMinutes = initialCheerInterval
        reminderPreset = ReminderPreset(rawValue: defaults.string(forKey: Key.reminderPreset) ?? "")
            ?? ReminderPreset.matching(water: initialWaterInterval, rest: initialRestInterval, cheer: initialCheerInterval)
        revealWindowOnReminder = defaults.object(forKey: Key.revealWindowOnReminder) as? Bool ?? true
        pomodoroFocusMinutes = initialFocusMinutes
        pomodoroShortBreakMinutes = initialShortBreakMinutes
        pomodoroLongBreakMinutes = initialLongBreakMinutes
        pomodoroLongBreakEvery = defaults.object(forKey: Key.pomodoroLongBreakEvery) as? Int ?? 4
        pomodoroMode = initialPomodoroMode
        pomodoroState = .idle
        completedFocusCount = defaults.object(forKey: Key.completedFocusCount) as? Int ?? 0
        isPomodoroPanelPresented = false
        isFavoritesPanelPresented = false
        pomodoroRemainingSeconds = Self.seconds(for: initialPomodoroMode, focusMinutes: initialFocusMinutes, shortBreakMinutes: initialShortBreakMinutes, longBreakMinutes: initialLongBreakMinutes)
        currentReminder = .cheer
        currentMood = .idle
        phrasePack = initialPhrasePack
        currentMessage = ReminderPhraseBook.startupLine(name: initialDogName, pack: initialPhrasePack)
        reminderPulse = 0
        pettingPulse = 0
        todayDateKey = currentTodayKey
        todayFocusCount = shouldKeepTodayStats ? defaults.integer(forKey: Key.todayFocusCount) : 0
        todayWaterRecords = shouldKeepTodayStats ? defaults.integer(forKey: Key.todayWaterRecords) : 0
        todayRestRecords = shouldKeepTodayStats ? defaults.integer(forKey: Key.todayRestRecords) : 0
        todayCheerRecords = shouldKeepTodayStats ? defaults.integer(forKey: Key.todayCheerRecords) : 0
        todayWaterReminders = shouldKeepTodayStats ? defaults.integer(forKey: Key.todayWaterReminders) : 0
        todayRestReminders = shouldKeepTodayStats ? defaults.integer(forKey: Key.todayRestReminders) : 0
        todayCheerReminders = shouldKeepTodayStats ? defaults.integer(forKey: Key.todayCheerReminders) : 0
        todayActivityEvents = shouldKeepTodayStats ? Self.loadTodayActivityEvents(from: defaults, key: Key.todayActivityEvents) : []
        todayPetTouches = shouldKeepTodayStats ? defaults.integer(forKey: Key.todayPetTouches) : 0
        clipboardHistoryEnabled = defaults.object(forKey: Key.clipboardHistoryEnabled) as? Bool ?? true
        clipboardMaxHistoryCount = initialClipboardMaxHistoryCount
        clipboardRecordTextEnabled = defaults.object(forKey: Key.clipboardRecordTextEnabled) as? Bool ?? true
        clipboardRecordImageEnabled = defaults.object(forKey: Key.clipboardRecordImageEnabled) as? Bool ?? true
        clipboardRecordFileEnabled = defaults.object(forKey: Key.clipboardRecordFileEnabled) as? Bool ?? true
        clipboardSensitiveFilteringEnabled = defaults.object(forKey: Key.clipboardSensitiveFilteringEnabled) as? Bool ?? true
        clipboardSensitiveKeywordsText = defaults.string(forKey: Key.clipboardSensitiveKeywordsText) ?? Self.defaultClipboardSensitiveKeywordsText
        clipboardSensitiveTokenHeuristicEnabled = defaults.object(forKey: Key.clipboardSensitiveTokenHeuristicEnabled) as? Bool ?? true
        let loadedClipboardHistory = Self.loadClipboardHistory(
            from: defaults,
            key: Key.clipboardHistory
        )
            .filter { item in
                guard item.kind == .image, let imageFilename = item.imageFilename else { return true }
                return FileManager.default.fileExists(atPath: initialClipboardImagesDirectory.appendingPathComponent(imageFilename).path)
            }
        clipboardHistory = Self.retainedClipboardHistoryItems(
            from: loadedClipboardHistory,
            maxCount: initialClipboardMaxHistoryCount
        )
        let loadedFavoriteEntries = Self.loadFavoriteEntries(from: defaults, key: Key.favoriteEntries)
        favoriteEntries = loadedFavoriteEntries.entries
        didMigrateFavoriteEntries = loadedFavoriteEntries.didMigrate
        pinnedQuickActions = Self.loadPinnedQuickActions(from: defaults, key: Key.pinnedQuickActions)
        hotkeysEnabled = defaults.object(forKey: Key.hotkeysEnabled) as? Bool ?? true
        hotkeys = Self.loadHotkeys(from: defaults, key: Key.hotkeys)
        failedHotkeyActions = []
        reminderScheduleRevision = 0
        if !shouldKeepTodayStats || didMigrateFavoriteEntries {
            persist()
        }
    }

    var pomodoroTotalSeconds: Int {
        durationSeconds(for: pomodoroMode)
    }

    var pomodoroProgress: Double {
        guard pomodoroTotalSeconds > 0 else { return 0 }
        let elapsed = max(0, pomodoroTotalSeconds - pomodoroRemainingSeconds)
        return min(1, max(0, Double(elapsed) / Double(pomodoroTotalSeconds)))
    }

    var pomodoroTimeText: String {
        let seconds = max(0, pomodoroRemainingSeconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var pomodoroStateText: String {
        switch pomodoroState {
        case .idle: return "准备开始"
        case .running: return "进行中"
        case .paused: return "已暂停"
        }
    }

    var pomodoroPrimaryActionTitle: String {
        pomodoroState == .running ? "暂停" : "开始"
    }

    var pomodoroPrimaryActionSymbol: String {
        pomodoroState == .running ? "pause.fill" : "play.fill"
    }

    func togglePomodoro() {
        if pomodoroState == .running {
            pausePomodoro()
        } else {
            startPomodoro()
        }
    }

    func startPomodoro() {
        guard pomodoroState != .running else { return }
        if pomodoroRemainingSeconds <= 0 {
            pomodoroRemainingSeconds = durationSeconds(for: pomodoroMode)
        }

        pomodoroState = .running
        currentMood = pomodoroMode == .focus ? .energized : .happy
        currentMessage = ReminderPhraseBook.pomodoroStart(mode: pomodoroMode, name: dogName, pack: phrasePack)
        reminderPulse += 1
        startPomodoroTimer()
    }

    func pausePomodoro() {
        guard pomodoroState == .running else { return }
        pomodoroState = .paused
        stopPomodoroTimer()
    }

    func resetPomodoro() {
        stopPomodoroTimer()
        pomodoroState = .idle
        pomodoroRemainingSeconds = durationSeconds(for: pomodoroMode)
    }

    func selectPomodoroMode(_ mode: PomodoroMode) {
        stopPomodoroTimer()
        pomodoroMode = mode
        pomodoroState = .idle
        pomodoroRemainingSeconds = durationSeconds(for: mode)
        persist()
    }

    func skipPomodoroSegment() {
        let nextMode = nextPomodoroMode(after: pomodoroMode)
        selectPomodoroMode(nextMode)
    }

    func resetPomodoroStats() {
        completedFocusCount = 0
        persist()
    }

    func triggerReminder(_ kind: ReminderKind) {
        refreshTodayActivityIfNeeded()
        incrementTodayReminder(kind)
        appendTodayActivityEvent(kind: .automaticReminder, reminder: kind)
        currentReminder = kind
        currentMood = kind.mood
        currentMessage = ReminderPhraseBook.message(for: kind, name: dogName, pack: phrasePack)
        reminderPulse += 1
        persist()

        scheduleMoodReset(after: 14)
    }

    func recordManualAction(_ kind: ReminderKind) {
        refreshTodayActivityIfNeeded()
        let count = incrementTodayRecord(kind)
        appendTodayActivityEvent(kind: .manualRecord, reminder: kind)
        currentReminder = kind
        currentMood = kind.mood
        currentMessage = ReminderPhraseBook.recordLine(for: kind, count: count, name: dogName, pack: phrasePack)
        reminderPulse += 1
        persist()
        scheduleMoodReset(after: 12)
    }

    func applyReminderPreset(_ preset: ReminderPreset) {
        reminderPreset = preset
        guard let intervals = preset.intervals else {
            persist()
            return
        }
        waterIntervalMinutes = intervals.water
        restIntervalMinutes = intervals.rest
        cheerIntervalMinutes = intervals.cheer
        persist()
    }

    func setReminderInterval(_ kind: ReminderKind, minutes: Double) {
        switch kind {
        case .water:
            waterIntervalMinutes = minutes
        case .rest:
            restIntervalMinutes = minutes
        case .cheer:
            cheerIntervalMinutes = minutes
        }
        updateReminderPresetFromIntervals()
    }

    private func updateReminderPresetFromIntervals() {
        let matchedPreset = ReminderPreset.matching(
            water: waterIntervalMinutes,
            rest: restIntervalMinutes,
            cheer: cheerIntervalMinutes
        )
        guard reminderPreset != matchedPreset else { return }
        reminderPreset = matchedPreset
        persist()
    }

    func petDog() {
        refreshTodayActivityIfNeeded()
        todayPetTouches += 1
        currentReminder = .cheer
        currentMood = .happy
        currentMessage = ReminderPhraseBook.pettingLine(name: dogName, pack: phrasePack)
        reminderPulse += 1
        pettingPulse += 1
        persist()
        scheduleMoodReset(after: 10)
    }

    func showStatusMessage(_ message: String, mood: DogMood = .happy, reminder: ReminderKind = .cheer, resetAfter seconds: TimeInterval = 8) {
        currentReminder = reminder
        currentMood = mood
        currentMessage = message
        reminderPulse += 1
        scheduleMoodReset(after: seconds)
    }

    func refreshTodayActivityIfNeeded() {
        let currentKey = Self.todayKey()
        guard todayDateKey != currentKey else { return }
        todayDateKey = currentKey
        resetTodayCounters()
        persist()
    }

    func resetTodayActivity() {
        todayDateKey = Self.todayKey()
        resetTodayCounters()
        currentReminder = .cheer
        currentMood = .idle
        currentMessage = "今天的记录已经清空，重新开始也很好。"
        reminderPulse += 1
        persist()
    }

    func recordClipboardText(_ text: String) {
        guard clipboardHistoryEnabled else { return }
        guard clipboardRecordTextEnabled else { return }

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        if clipboardSensitiveFilteringEnabled {
            guard !Self.looksSensitive(
                cleanText,
                keywords: clipboardSensitiveKeywords,
                detectsComplexToken: clipboardSensitiveTokenHeuristicEnabled
            ) else { return }
        }

        if clipboardHistory.first?.kind == .text, clipboardHistory.first?.text == cleanText {
            return
        }

        let duplicateItems = clipboardHistory.filter { $0.kind == .text && $0.text == cleanText }
        let pinState = clipboardPinState(from: duplicateItems)
        clipboardHistory.removeAll { $0.kind == .text && $0.text == cleanText }
        clipboardHistory.insert(
            ClipboardHistoryItem(text: cleanText, isPinned: pinState.isPinned, pinnedAt: pinState.pinnedAt),
            at: 0
        )
        sortClipboardHistory()
        trimClipboardHistory()
        persist()
    }

    func recordClipboardImage(_ image: NSImage) {
        guard clipboardHistoryEnabled else { return }
        guard clipboardRecordImageEnabled else { return }
        guard let tiffData = image.tiffRepresentation, !tiffData.isEmpty else { return }

        let directory = clipboardImagesDirectory
        let copiedAt = Date()
        let processingTask = Task.detached(priority: .utility) {
            Self.prepareClipboardImage(tiffData: tiffData, directory: directory, copiedAt: copiedAt)
        }

        Task { @MainActor [weak self] in
            guard let self,
                  let preparedImage = await processingTask.value
            else { return }
            self.finishRecordingClipboardImage(preparedImage)
        }
    }

    private func finishRecordingClipboardImage(_ preparedImage: PreparedClipboardImage) {
        guard clipboardHistoryEnabled, clipboardRecordImageEnabled else {
            removeImageFile(named: preparedImage.filename)
            return
        }

        if clipboardHistory.first?.kind == .image,
           clipboardHistory.first?.contentHash == preparedImage.contentHash {
            removeImageFile(named: preparedImage.filename)
            return
        }

        let duplicateItems = clipboardHistory.filter {
            $0.kind == .image && $0.contentHash == preparedImage.contentHash
        }
        let pinState = clipboardPinState(from: duplicateItems)
        clipboardHistory.removeAll { item in
            item.kind == .image && item.contentHash == preparedImage.contentHash
        }
        for item in duplicateItems {
            removeImageFileIfNeeded(for: item)
        }

        clipboardHistory.insert(
            ClipboardHistoryItem(
                imageFilename: preparedImage.filename,
                imagePixelWidth: preparedImage.pixelWidth,
                imagePixelHeight: preparedImage.pixelHeight,
                contentHash: preparedImage.contentHash,
                copiedAt: preparedImage.copiedAt,
                isPinned: pinState.isPinned,
                pinnedAt: pinState.pinnedAt
            ),
            at: 0
        )
        sortClipboardHistory()
        trimClipboardHistory()
        persist()
    }

    func recordClipboardFiles(_ urls: [URL]) {
        guard clipboardHistoryEnabled else { return }
        guard clipboardRecordFileEnabled else { return }
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return }

        let filePaths = fileURLs.map(\.path)
        let contentHash = Self.fileContentHash(for: fileURLs)
        if clipboardHistory.first?.kind == .file, clipboardHistory.first?.contentHash == contentHash {
            return
        }

        let duplicateItems = clipboardHistory.filter { $0.kind == .file && $0.contentHash == contentHash }
        let pinState = clipboardPinState(from: duplicateItems)
        clipboardHistory.removeAll { $0.kind == .file && $0.contentHash == contentHash }
        clipboardHistory.insert(
            ClipboardHistoryItem(
                filePaths: filePaths,
                fileNames: fileURLs.map { $0.lastPathComponent },
                fileTypeDescription: Self.fileTypeDescription(for: fileURLs),
                fileTotalByteCount: Self.totalByteCount(for: fileURLs),
                contentHash: contentHash,
                isPinned: pinState.isPinned,
                pinnedAt: pinState.pinnedAt
            ),
            at: 0
        )
        sortClipboardHistory()
        trimClipboardHistory()
        persist()
    }

    func image(for item: ClipboardHistoryItem) -> NSImage? {
        guard item.kind == .image, let imageFilename = item.imageFilename else { return nil }
        return NSImage(contentsOf: clipboardImagesDirectory.appendingPathComponent(imageFilename))
    }

    func fileURLs(for item: ClipboardHistoryItem) -> [URL] {
        guard item.kind == .file else { return [] }
        return (item.filePaths ?? [])
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var secondaryQuickActions: [QuickAction] {
        QuickAction.secondaryDisplayOrder.filter { !pinnedQuickActions.contains($0) }
    }

    func isQuickActionPinned(_ action: QuickAction) -> Bool {
        pinnedQuickActions.contains(action)
    }

    func setQuickAction(_ action: QuickAction, pinned: Bool) {
        if pinned {
            guard !pinnedQuickActions.contains(action) else { return }
            guard pinnedQuickActions.count < QuickAction.maximumPinnedCount else { return }
            pinnedQuickActions.append(action)
        } else {
            pinnedQuickActions.removeAll { $0 == action }
        }
        persist()
    }

    func movePinnedQuickAction(_ action: QuickAction, by offset: Int) {
        guard let sourceIndex = pinnedQuickActions.firstIndex(of: action) else { return }
        let destinationIndex = sourceIndex + offset
        guard pinnedQuickActions.indices.contains(destinationIndex) else { return }
        pinnedQuickActions.swapAt(sourceIndex, destinationIndex)
        persist()
    }

    func resetPinnedQuickActions() {
        pinnedQuickActions = QuickAction.defaultPinned
        persist()
    }

    func clearClipboardHistory() {
        for item in clipboardHistory {
            removeImageFileIfNeeded(for: item)
        }
        clipboardHistory = []
        persist()
    }

    func removeClipboardHistoryItem(_ item: ClipboardHistoryItem) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == item.id }) else { return }
        let removedItem = clipboardHistory.remove(at: index)
        removeImageFileIfNeeded(for: removedItem)
        persist()
    }

    @discardableResult
    func setClipboardHistoryItem(_ item: ClipboardHistoryItem, pinned: Bool) -> Bool {
        setClipboardHistoryItem(id: item.id, pinned: pinned)
    }

    @discardableResult
    func setClipboardHistoryItem(id: ClipboardHistoryItem.ID, pinned: Bool) -> Bool {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == id }) else { return false }
        guard clipboardHistory[index].isPinned != pinned else { return false }

        var updatedHistory = clipboardHistory
        updatedHistory[index].isPinned = pinned
        updatedHistory[index].pinnedAt = pinned ? Date() : nil
        clipboardHistory = Self.sortedClipboardHistory(updatedHistory)
        trimClipboardHistory()
        persist()
        return true
    }

    @discardableResult
    func toggleClipboardHistoryItemPinned(_ item: ClipboardHistoryItem) -> Bool {
        toggleClipboardHistoryItemPinned(id: item.id)
    }

    @discardableResult
    func toggleClipboardHistoryItemPinned(id: ClipboardHistoryItem.ID) -> Bool {
        guard let currentItem = clipboardHistory.first(where: { $0.id == id }) else { return false }
        return setClipboardHistoryItem(id: id, pinned: !currentItem.isPinned)
    }

    var favoriteRootNodes: [FavoriteTreeNode] {
        let entriesByParentID = Dictionary(grouping: favoriteEntries, by: \.parentFolderID)
        return favoriteTreeNodes(parentID: nil, entriesByParentID: entriesByParentID, visitedIDs: [])
    }

    var favoriteFolders: [FavoriteEntry] {
        favoriteEntries
            .filter(\.isFolder)
            .sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
    }

    func favoriteTreeNodes(parentID: FavoriteEntry.ID?) -> [FavoriteTreeNode] {
        let entriesByParentID = Dictionary(grouping: favoriteEntries, by: \.parentFolderID)
        return favoriteTreeNodes(parentID: parentID, entriesByParentID: entriesByParentID, visitedIDs: [])
    }

    private func favoriteTreeNodes(
        parentID: FavoriteEntry.ID?,
        entriesByParentID: [FavoriteEntry.ID?: [FavoriteEntry]],
        visitedIDs: Set<FavoriteEntry.ID>
    ) -> [FavoriteTreeNode] {
        (entriesByParentID[parentID] ?? [])
            .sorted(by: favoriteEntrySort)
            .filter { !visitedIDs.contains($0.id) }
            .map { entry in
                var nextVisitedIDs = visitedIDs
                nextVisitedIDs.insert(entry.id)
                return FavoriteTreeNode(
                    entry: entry,
                    children: favoriteTreeNodes(
                        parentID: entry.id,
                        entriesByParentID: entriesByParentID,
                        visitedIDs: nextVisitedIDs
                    )
                )
            }
    }

    func addFavoriteEntry(alias: String, target: String, kind: FavoriteEntryKind, parentFolderID: FavoriteEntry.ID?) {
        let cleanAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlias.isEmpty else { return }
        guard kind.isFolder || !cleanTarget.isEmpty else { return }
        favoriteEntries.append(
            FavoriteEntry(
                alias: cleanAlias,
                target: kind.isFolder ? "" : cleanTarget,
                kind: kind,
                parentFolderID: parentFolderID
            )
        )
        persist()
    }

    func updateFavoriteEntry(_ entry: FavoriteEntry) {
        guard let index = favoriteEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.alias = updated.alias.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.target = updated.target.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.groupName = updated.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.alias.isEmpty else { return }
        guard updated.kind.isFolder || !updated.target.isEmpty else { return }
        if updated.kind.isFolder {
            updated.target = ""
            if updated.parentFolderID == updated.id || isFavoriteFolder(updated.parentFolderID, descendantOf: updated.id) {
                updated.parentFolderID = nil
            }
        }
        updated.updatedAt = Date()
        favoriteEntries[index] = updated
        persist()
    }

    func removeFavoriteEntry(_ entry: FavoriteEntry) {
        let removedIDs = favoriteDescendantIDs(of: entry.id).union([entry.id])
        favoriteEntries.removeAll { removedIDs.contains($0.id) }
        persist()
    }

    private func favoriteEntrySort(_ lhs: FavoriteEntry, _ rhs: FavoriteEntry) -> Bool {
        if lhs.isFolder != rhs.isFolder {
            return lhs.isFolder
        }
        return lhs.alias.localizedCaseInsensitiveCompare(rhs.alias) == .orderedAscending
    }

    private func favoriteDescendantIDs(of folderID: FavoriteEntry.ID) -> Set<FavoriteEntry.ID> {
        let childIDs = favoriteEntries.filter { $0.parentFolderID == folderID }.map(\.id)
        return childIDs.reduce(into: Set<FavoriteEntry.ID>()) { result, childID in
            result.insert(childID)
            result.formUnion(favoriteDescendantIDs(of: childID))
        }
    }

    private func isFavoriteFolder(_ folderID: FavoriteEntry.ID?, descendantOf ancestorID: FavoriteEntry.ID) -> Bool {
        guard let folderID else { return false }
        if folderID == ancestorID { return true }
        guard let parentID = favoriteEntries.first(where: { $0.id == folderID })?.parentFolderID else { return false }
        return isFavoriteFolder(parentID, descendantOf: ancestorID)
    }

    func hotkey(for action: HotkeyAction) -> WorkdogHotkey? {
        hotkeys[action] ?? action.defaultHotkey
    }

    func setHotkey(_ hotkey: WorkdogHotkey?, for action: HotkeyAction) {
        hotkeys[action] = hotkey
        persist()
    }

    func resetHotkeysToDefaults() {
        hotkeys = Self.defaultHotkeys()
        hotkeysEnabled = true
        persist()
    }

    func updateFailedHotkeyActions(_ actions: Set<HotkeyAction>) {
        failedHotkeyActions = actions
    }

    func noteReminderScheduleChanged() {
        reminderScheduleRevision += 1
    }

    func resetToDefaults() {
        dogName = "快乐小狗"
        bodyShape = .round
        coat = .golden
        avatarScale = Self.defaultAvatarScale
        remindersEnabled = true
        waterEnabled = true
        restEnabled = true
        cheerEnabled = true
        waterIntervalMinutes = 45
        restIntervalMinutes = 90
        cheerIntervalMinutes = 120
        reminderPreset = .standard
        revealWindowOnReminder = true
        clipboardHistoryEnabled = true
        clipboardMaxHistoryCount = Self.defaultClipboardHistoryCount
        clipboardRecordTextEnabled = true
        clipboardRecordImageEnabled = true
        clipboardRecordFileEnabled = true
        clipboardSensitiveFilteringEnabled = true
        clipboardSensitiveKeywordsText = Self.defaultClipboardSensitiveKeywordsText
        clipboardSensitiveTokenHeuristicEnabled = true
        resetPinnedQuickActions()
        resetHotkeysToDefaults()
        for item in clipboardHistory {
            removeImageFileIfNeeded(for: item)
        }
        clipboardHistory = []
        pomodoroFocusMinutes = PomodoroMode.focus.defaultMinutes
        pomodoroShortBreakMinutes = PomodoroMode.shortBreak.defaultMinutes
        pomodoroLongBreakMinutes = PomodoroMode.longBreak.defaultMinutes
        pomodoroLongBreakEvery = 4
        completedFocusCount = 0
        resetTodayCounters()
        selectPomodoroMode(.focus)
        phrasePack = .defaultPack
        currentReminder = .cheer
        currentMood = .idle
        currentMessage = ReminderPhraseBook.startupLine(name: dogName, pack: phrasePack)
        reminderPulse += 1
        persist()
    }

    func resetPhrasePackToDefaults() {
        phrasePack = .defaultPack
        currentReminder = .cheer
        currentMood = .idle
        currentMessage = ReminderPhraseBook.startupLine(name: dogName, pack: phrasePack)
        reminderPulse += 1
    }

    private func persist() {
        defaults.set(dogName, forKey: Key.dogName)
        defaults.set(bodyShape.rawValue, forKey: Key.bodyShape)
        defaults.set(coat.rawValue, forKey: Key.coat)
        defaults.set(avatarScale, forKey: Key.avatarScale)
        defaults.set(remindersEnabled, forKey: Key.remindersEnabled)
        defaults.set(waterEnabled, forKey: Key.waterEnabled)
        defaults.set(restEnabled, forKey: Key.restEnabled)
        defaults.set(cheerEnabled, forKey: Key.cheerEnabled)
        defaults.set(waterIntervalMinutes, forKey: Key.waterIntervalMinutes)
        defaults.set(restIntervalMinutes, forKey: Key.restIntervalMinutes)
        defaults.set(cheerIntervalMinutes, forKey: Key.cheerIntervalMinutes)
        defaults.set(reminderPreset.rawValue, forKey: Key.reminderPreset)
        defaults.set(revealWindowOnReminder, forKey: Key.revealWindowOnReminder)
        defaults.set(pomodoroFocusMinutes, forKey: Key.pomodoroFocusMinutes)
        defaults.set(pomodoroShortBreakMinutes, forKey: Key.pomodoroShortBreakMinutes)
        defaults.set(pomodoroLongBreakMinutes, forKey: Key.pomodoroLongBreakMinutes)
        defaults.set(pomodoroLongBreakEvery, forKey: Key.pomodoroLongBreakEvery)
        defaults.set(pomodoroMode.rawValue, forKey: Key.pomodoroMode)
        defaults.set(completedFocusCount, forKey: Key.completedFocusCount)
        defaults.set(todayDateKey, forKey: Key.todayDateKey)
        defaults.set(todayFocusCount, forKey: Key.todayFocusCount)
        defaults.set(todayWaterRecords, forKey: Key.todayWaterRecords)
        defaults.set(todayRestRecords, forKey: Key.todayRestRecords)
        defaults.set(todayCheerRecords, forKey: Key.todayCheerRecords)
        defaults.set(todayWaterReminders, forKey: Key.todayWaterReminders)
        defaults.set(todayRestReminders, forKey: Key.todayRestReminders)
        defaults.set(todayCheerReminders, forKey: Key.todayCheerReminders)
        if let data = try? JSONEncoder().encode(todayActivityEvents) {
            defaults.set(data, forKey: Key.todayActivityEvents)
        }
        defaults.set(todayPetTouches, forKey: Key.todayPetTouches)
        defaults.set(clipboardHistoryEnabled, forKey: Key.clipboardHistoryEnabled)
        defaults.set(clipboardMaxHistoryCount, forKey: Key.clipboardMaxHistoryCount)
        defaults.set(clipboardRecordTextEnabled, forKey: Key.clipboardRecordTextEnabled)
        defaults.set(clipboardRecordImageEnabled, forKey: Key.clipboardRecordImageEnabled)
        defaults.set(clipboardRecordFileEnabled, forKey: Key.clipboardRecordFileEnabled)
        defaults.set(clipboardSensitiveFilteringEnabled, forKey: Key.clipboardSensitiveFilteringEnabled)
        defaults.set(clipboardSensitiveKeywordsText, forKey: Key.clipboardSensitiveKeywordsText)
        defaults.set(clipboardSensitiveTokenHeuristicEnabled, forKey: Key.clipboardSensitiveTokenHeuristicEnabled)
        if let data = try? JSONEncoder().encode(pinnedQuickActions.map(\.rawValue)) {
            defaults.set(data, forKey: Key.pinnedQuickActions)
        }
        if let data = try? JSONEncoder().encode(clipboardHistory) {
            defaults.set(data, forKey: Key.clipboardHistory)
        }
        if let data = try? JSONEncoder().encode(favoriteEntries) {
            defaults.set(data, forKey: Key.favoriteEntries)
        }
        defaults.set(hotkeysEnabled, forKey: Key.hotkeysEnabled)
        if let data = try? JSONEncoder().encode(Self.codableHotkeys(from: hotkeys)) {
            defaults.set(data, forKey: Key.hotkeys)
        }
        if let data = try? JSONEncoder().encode(phrasePack) {
            defaults.set(data, forKey: Key.phrasePack)
        }
    }

    private func startPomodoroTimer() {
        stopPomodoroTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickPomodoro()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pomodoroTimer = timer
    }

    private func stopPomodoroTimer() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
    }

    private func tickPomodoro() {
        guard pomodoroState == .running else { return }
        if pomodoroRemainingSeconds > 1 {
            pomodoroRemainingSeconds -= 1
        } else {
            completePomodoroSegment()
        }
    }

    private func completePomodoroSegment() {
        let finishedMode = pomodoroMode
        stopPomodoroTimer()
        pomodoroState = .idle

        if finishedMode == .focus {
            completedFocusCount += 1
            refreshTodayActivityIfNeeded()
            todayFocusCount += 1
        }

        let message = ReminderPhraseBook.pomodoroCompletion(
            mode: finishedMode,
            completedFocusCount: completedFocusCount,
            longBreakEvery: pomodoroLongBreakEvery,
            name: dogName,
            pack: phrasePack
        )
        currentReminder = finishedMode == .focus ? .cheer : .rest
        currentMood = finishedMode == .focus ? .proud : .energized
        currentMessage = message
        reminderPulse += 1

        pomodoroMode = nextPomodoroMode(after: finishedMode)
        pomodoroRemainingSeconds = durationSeconds(for: pomodoroMode)
        persist()
        scheduleMoodReset(after: 18)
        onPomodoroCompleted?(finishedMode, message)
    }

    private func nextPomodoroMode(after mode: PomodoroMode) -> PomodoroMode {
        switch mode {
        case .focus:
            return completedFocusCount > 0 && completedFocusCount % max(1, pomodoroLongBreakEvery) == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    private func durationSeconds(for mode: PomodoroMode) -> Int {
        Self.seconds(for: mode, focusMinutes: pomodoroFocusMinutes, shortBreakMinutes: pomodoroShortBreakMinutes, longBreakMinutes: pomodoroLongBreakMinutes)
    }

    private static func seconds(for mode: PomodoroMode, focusMinutes: Double, shortBreakMinutes: Double, longBreakMinutes: Double) -> Int {
        let minutes: Double
        switch mode {
        case .focus:
            minutes = focusMinutes
        case .shortBreak:
            minutes = shortBreakMinutes
        case .longBreak:
            minutes = longBreakMinutes
        }
        return max(60, Int(minutes.rounded()) * 60)
    }

    private func syncIdlePomodoroDuration(for mode: PomodoroMode) {
        if pomodoroState == .idle && pomodoroMode == mode {
            pomodoroRemainingSeconds = durationSeconds(for: mode)
        }
    }

    private func scheduleMoodReset(after seconds: TimeInterval) {
        resetMoodWorkItem?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            self?.currentMood = .idle
        }
        resetMoodWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: reset)
    }

    private func incrementTodayReminder(_ kind: ReminderKind) {
        switch kind {
        case .water:
            todayWaterReminders += 1
        case .rest:
            todayRestReminders += 1
        case .cheer:
            todayCheerReminders += 1
        }
    }

    private func appendTodayActivityEvent(kind: WorkdogActivityEventKind, reminder: ReminderKind) {
        todayActivityEvents.insert(
            WorkdogActivityEvent(kind: kind, reminder: reminder),
            at: 0
        )
        if todayActivityEvents.count > 200 {
            todayActivityEvents = Array(todayActivityEvents.prefix(200))
        }
    }

    private func incrementTodayRecord(_ kind: ReminderKind) -> Int {
        switch kind {
        case .water:
            todayWaterRecords += 1
            return todayWaterRecords
        case .rest:
            todayRestRecords += 1
            return todayRestRecords
        case .cheer:
            todayCheerRecords += 1
            return todayCheerRecords
        }
    }

    private func resetTodayCounters() {
        todayFocusCount = 0
        todayWaterRecords = 0
        todayRestRecords = 0
        todayCheerRecords = 0
        todayWaterReminders = 0
        todayRestReminders = 0
        todayCheerReminders = 0
        todayActivityEvents = []
        todayPetTouches = 0
    }

    private static func todayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func loadClipboardHistory(from defaults: UserDefaults, key: String) -> [ClipboardHistoryItem] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
        else { return [] }

        return sortedClipboardHistory(items)
    }

    private static func loadFavoriteEntries(from defaults: UserDefaults, key: String) -> (entries: [FavoriteEntry], didMigrate: Bool) {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([FavoriteEntry].self, from: data)
        else { return ([], false) }

        var migratedEntries = entries.filter {
            !$0.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ($0.kind.isFolder || !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        var folderIDsByName: [String: UUID] = [:]
        let legacyGroupNames = Set(
            migratedEntries
                .map { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        var didMigrate = !legacyGroupNames.isEmpty
        for groupName in legacyGroupNames {
            let folder = FavoriteEntry(alias: groupName, target: "", kind: .folder)
            migratedEntries.append(folder)
            folderIDsByName[groupName] = folder.id
        }

        for index in migratedEntries.indices {
            guard migratedEntries[index].parentFolderID == nil,
                  !migratedEntries[index].groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            migratedEntries[index].parentFolderID = folderIDsByName[migratedEntries[index].groupTitle]
            migratedEntries[index].groupName = ""
        }

        let entriesByID = Dictionary(uniqueKeysWithValues: migratedEntries.map { ($0.id, $0) })
        let folderIDs = Set(migratedEntries.filter(\.isFolder).map(\.id))
        for index in migratedEntries.indices {
            guard let parentFolderID = migratedEntries[index].parentFolderID else { continue }
            if !folderIDs.contains(parentFolderID)
                || parentFolderID == migratedEntries[index].id
                || favoriteParentChainHasCycle(for: migratedEntries[index], entriesByID: entriesByID) {
                migratedEntries[index].parentFolderID = nil
                didMigrate = true
            }
        }

        didMigrate = didMigrate || migratedEntries.count != entries.count
        return (migratedEntries, didMigrate)
    }

    private static func favoriteParentChainHasCycle(
        for entry: FavoriteEntry,
        entriesByID: [FavoriteEntry.ID: FavoriteEntry]
    ) -> Bool {
        var visitedIDs: Set<FavoriteEntry.ID> = [entry.id]
        var currentParentID = entry.parentFolderID

        while let parentID = currentParentID {
            guard !visitedIDs.contains(parentID) else { return true }
            visitedIDs.insert(parentID)
            currentParentID = entriesByID[parentID]?.parentFolderID
        }
        return false
    }

    private static func loadTodayActivityEvents(from defaults: UserDefaults, key: String) -> [WorkdogActivityEvent] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([WorkdogActivityEvent].self, from: data)
        else { return [] }

        return Array(items.sorted { $0.happenedAt > $1.happenedAt }.prefix(200))
    }

    private static func loadPinnedQuickActions(from defaults: UserDefaults, key: String) -> [QuickAction] {
        guard let data = defaults.data(forKey: key),
              let rawValues = try? JSONDecoder().decode([String].self, from: data)
        else { return QuickAction.defaultPinned }

        var actions: [QuickAction] = []
        for rawValue in rawValues {
            guard let action = QuickAction(rawValue: rawValue),
                  !actions.contains(action)
            else { continue }
            actions.append(action)
            if actions.count == QuickAction.allCases.count {
                break
            }
        }
        if QuickAction.legacyDefaultPinnedVariants.contains(actions) || actions.isEmpty {
            return QuickAction.defaultPinned
        }
        if actions.count > QuickAction.maximumPinnedCount, actions.contains(.settings) {
            actions.removeAll { $0 == .settings }
        }
        if actions.count > QuickAction.maximumPinnedCount {
            actions = Array(actions.prefix(QuickAction.maximumPinnedCount))
        }
        return actions
    }

    private static func loadPhrasePack(from defaults: UserDefaults, key: String) -> WorkdogPhrasePack {
        guard let data = defaults.data(forKey: key),
              let pack = try? JSONDecoder().decode(WorkdogPhrasePack.self, from: data)
        else { return .defaultPack }

        return pack
    }

    private static func loadHotkeys(from defaults: UserDefaults, key: String) -> [HotkeyAction: WorkdogHotkey?] {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: WorkdogHotkey?].self, from: data)
        else { return defaultHotkeys() }

        var result = defaultHotkeys()
        for action in HotkeyAction.allCases {
            if saved.keys.contains(action.rawValue) {
                let savedHotkey = saved[action.rawValue] ?? nil
                if let savedHotkey, action.legacyDefaultHotkeys.contains(savedHotkey) {
                    result[action] = action.defaultHotkey
                } else {
                    result[action] = savedHotkey
                }
            }
        }
        return result
    }

    private static func defaultHotkeys() -> [HotkeyAction: WorkdogHotkey?] {
        Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, Optional($0.defaultHotkey)) })
    }

    private static func codableHotkeys(from hotkeys: [HotkeyAction: WorkdogHotkey?]) -> [String: WorkdogHotkey?] {
        Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { action in
            (action.rawValue, hotkeys[action] ?? action.defaultHotkey)
        })
    }

    private func trimClipboardHistory() {
        let retainedItems = Self.retainedClipboardHistoryItems(
            from: clipboardHistory,
            maxCount: clipboardMaxHistoryCount
        )
        let retainedIDs = Set(retainedItems.map(\.id))
        let removedItems = clipboardHistory.filter { !retainedIDs.contains($0.id) }
        clipboardHistory = retainedItems
        for item in removedItems {
            removeImageFileIfNeeded(for: item)
        }
    }

    private func sortClipboardHistory() {
        clipboardHistory = Self.sortedClipboardHistory(clipboardHistory)
    }

    private func clipboardPinState(from items: [ClipboardHistoryItem]) -> ClipboardPinState {
        let item = items.first(where: { $0.isPinned }) ?? items.first
        return ClipboardPinState(isPinned: item?.isPinned ?? false, pinnedAt: item?.pinnedAt)
    }

    private static func retainedClipboardHistoryItems(
        from items: [ClipboardHistoryItem],
        maxCount: Int
    ) -> [ClipboardHistoryItem] {
        let sortedItems = sortedClipboardHistory(items)
        let pinnedItems = sortedItems.filter(\.isPinned)
        let unpinnedItems = sortedItems.filter { !$0.isPinned }
        let retainedUnpinnedCount = max(0, max(1, maxCount) - pinnedItems.count)
        return pinnedItems + Array(unpinnedItems.prefix(retainedUnpinnedCount))
    }

    private static func sortedClipboardHistory(_ items: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            if lhs.clipboardSortDate != rhs.clipboardSortDate {
                return lhs.clipboardSortDate > rhs.clipboardSortDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func normalizedClipboardHistoryCount(_ rawValue: Int) -> Int {
        clipboardHistoryCountOptions.min { lhs, rhs in
            abs(lhs - rawValue) < abs(rhs - rawValue)
        } ?? defaultClipboardHistoryCount
    }

    private func removeImageFileIfNeeded(for item: ClipboardHistoryItem) {
        guard item.kind == .image, let imageFilename = item.imageFilename else { return }
        removeImageFile(named: imageFilename)
    }

    private func removeImageFile(named filename: String) {
        try? FileManager.default.removeItem(at: clipboardImagesDirectory.appendingPathComponent(filename))
    }

    private static func makeClipboardImagesDirectory() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = baseDirectory
            .appendingPathComponent("HappyWorkdog", isDirectory: true)
            .appendingPathComponent("ClipboardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private nonisolated static func prepareClipboardImage(
        tiffData: Data,
        directory: URL,
        copiedAt: Date
    ) -> PreparedClipboardImage? {
        guard let pngData = pngData(fromTIFFData: tiffData), !pngData.isEmpty else { return nil }
        let hash = sha256Hex(for: pngData)
        let filename = "\(UUID().uuidString).png"
        let fileURL = directory.appendingPathComponent(filename)

        do {
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }

        let pixelSize = pixelSize(forPNGData: pngData)
        return PreparedClipboardImage(
            filename: filename,
            pixelWidth: pixelSize.width,
            pixelHeight: pixelSize.height,
            contentHash: hash,
            copiedAt: copiedAt
        )
    }

    private nonisolated static func pngData(fromTIFFData data: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: data)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private nonisolated static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func pixelSize(forPNGData data: Data) -> (width: Int, height: Int) {
        if let bitmap = NSBitmapImageRep(data: data) {
            return (bitmap.pixelsWide, bitmap.pixelsHigh)
        }
        return (1, 1)
    }

    private static func fileContentHash(for urls: [URL]) -> String {
        let value = urls
            .map { $0.path }
            .joined(separator: "\n")
        return sha256Hex(for: Data(value.utf8))
    }

    private static func fileTypeDescription(for urls: [URL]) -> String {
        guard urls.count == 1, let url = urls.first else {
            return "\(urls.count) 个文件"
        }

        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return "文件夹"
        }

        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.localizedDescription ?? "文件"
        }

        return url.pathExtension.isEmpty ? "文件" : "\(url.pathExtension.uppercased()) 文件"
    }

    private static func totalByteCount(for urls: [URL]) -> Int64? {
        var total: Int64 = 0
        var hasKnownSize = false

        for url in urls {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { continue }
            total += Int64(size)
            hasKnownSize = true
        }

        return hasKnownSize ? total : nil
    }

    nonisolated static func looksSensitive(
        _ text: String,
        keywords: [String] = defaultClipboardSensitiveKeywords,
        detectsComplexToken: Bool = true
    ) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count >= 8 else { return false }
        let cleanKeywords = normalizedKeywords(from: keywords)

        if let jsonObject = structuredJSONObject(from: compact) {
            return jsonObjectLooksSensitive(jsonObject, keywords: cleanKeywords)
        }

        guard compact.count <= 128 else { return false }
        guard !compact.contains(where: { $0.isWhitespace }) else { return false }

        let lowercased = compact.lowercased()
        if cleanKeywords.raw.contains(where: { lowercased.contains($0) }) {
            return true
        }

        guard detectsComplexToken else { return false }

        let scalarSet = CharacterSet(charactersIn: compact)
        let hasLowercase = scalarSet.intersection(.lowercaseLetters).isEmpty == false
        let hasUppercase = scalarSet.intersection(.uppercaseLetters).isEmpty == false
        let hasDigit = scalarSet.intersection(.decimalDigits).isEmpty == false
        let symbolCharacters = CharacterSet.alphanumerics.inverted
        let hasSymbol = scalarSet.intersection(symbolCharacters).isEmpty == false

        return [hasLowercase, hasUppercase, hasDigit, hasSymbol].filter { $0 }.count >= 3
    }

    nonisolated static func parseClipboardSensitiveKeywords(_ text: String) -> [String] {
        var seen: Set<String> = []
        var keywords: [String] = []

        for rawKeyword in text.split(whereSeparator: isKeywordSeparator) {
            let keyword = String(rawKeyword).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty else { continue }
            let lookupKey = keyword.lowercased()
            guard !seen.contains(lookupKey) else { continue }
            seen.insert(lookupKey)
            keywords.append(keyword)
        }

        return keywords
    }

    private nonisolated static func structuredJSONObject(from text: String) -> Any? {
        guard let first = text.first, let last = text.last else { return nil }
        guard (first == "{" && last == "}") || (first == "[" && last == "]") else { return nil }
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private nonisolated static func jsonObjectLooksSensitive(
        _ value: Any,
        keywords: (raw: [String], json: [String])
    ) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                if isSensitiveJSONKey(key, keywords: keywords.json), jsonValueIsPresent(nestedValue) {
                    return true
                }
                if jsonObjectLooksSensitive(nestedValue, keywords: keywords) {
                    return true
                }
            }
            return false
        }

        if let array = value as? [Any] {
            return array.contains { jsonObjectLooksSensitive($0, keywords: keywords) }
        }

        return false
    }

    private nonisolated static func isSensitiveJSONKey(_ key: String, keywords: [String]) -> Bool {
        let normalized = key
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return keywords.contains { normalized.contains($0) }
    }

    private nonisolated static func jsonValueIsPresent(_ value: Any) -> Bool {
        if value is NSNull {
            return false
        }

        if let string = value as? String {
            return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if let array = value as? [Any] {
            return !array.isEmpty
        }

        if let dictionary = value as? [String: Any] {
            return !dictionary.isEmpty
        }

        return true
    }

    private nonisolated static func normalizedKeywords(from keywords: [String]) -> (raw: [String], json: [String]) {
        var rawSeen: Set<String> = []
        var jsonSeen: Set<String> = []
        var rawKeywords: [String] = []
        var jsonKeywords: [String] = []

        for keyword in keywords {
            let rawKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !rawKeyword.isEmpty, !rawSeen.contains(rawKeyword) {
                rawSeen.insert(rawKeyword)
                rawKeywords.append(rawKeyword)
            }

            let jsonKeyword = rawKeyword.filter { $0.isLetter || $0.isNumber }
            if !jsonKeyword.isEmpty, !jsonSeen.contains(jsonKeyword) {
                jsonSeen.insert(jsonKeyword)
                jsonKeywords.append(jsonKeyword)
            }
        }

        return (rawKeywords, jsonKeywords)
    }

    private nonisolated static func isKeywordSeparator(_ character: Character) -> Bool {
        character.isWhitespace || character == "," || character == "，" || character == ";" || character == "；"
    }
}
