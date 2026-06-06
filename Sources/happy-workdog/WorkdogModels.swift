import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ClipboardHistoryKind: String, Codable {
    case text
    case image
    case file
}

enum WorkdogActivityEventKind: String, Codable, CaseIterable, Identifiable {
    case manualRecord
    case automaticReminder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualRecord: return "手动记录"
        case .automaticReminder: return "自动提醒"
        }
    }
}

struct WorkdogActivityEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: WorkdogActivityEventKind
    let reminder: ReminderKind
    let happenedAt: Date

    init(id: UUID = UUID(), kind: WorkdogActivityEventKind, reminder: ReminderKind, happenedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.reminder = reminder
        self.happenedAt = happenedAt
    }
}

enum QuickAction: String, CaseIterable, Identifiable, Codable, Hashable {
    case pomodoro
    case favorites
    case clipboard
    case screenshot
    case water
    case rest
    case cheer
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pomodoro: return "番茄钟"
        case .favorites: return "常用入口"
        case .clipboard: return "剪贴板"
        case .screenshot: return "截图"
        case .water: return "喝水"
        case .rest: return "休息"
        case .cheer: return "打气"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .pomodoro: return "timer"
        case .favorites: return "star.fill"
        case .clipboard: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
        case .water: return ReminderKind.water.symbol
        case .rest: return ReminderKind.rest.symbol
        case .cheer: return ReminderKind.cheer.symbol
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pomodoro: return PomodoroMode.focus.tint
        case .favorites: return Color(red: 0.76, green: 0.52, blue: 0.18)
        case .clipboard: return Color(red: 0.18, green: 0.48, blue: 0.72)
        case .screenshot: return Color(red: 0.28, green: 0.58, blue: 0.42)
        case .water: return ReminderKind.water.tint
        case .rest: return ReminderKind.rest.tint
        case .cheer: return ReminderKind.cheer.tint
        case .settings: return Color(red: 0.34, green: 0.42, blue: 0.56)
        }
    }

    static let defaultPinned: [QuickAction] = [.pomodoro, .favorites, .clipboard, .screenshot]
    static let secondaryDisplayOrder: [QuickAction] = [.settings, .water, .rest, .cheer, .pomodoro, .favorites, .clipboard, .screenshot]
    static let legacyDefaultPinnedVariants: [[QuickAction]] = [
        [.pomodoro, .clipboard, .screenshot],
    ]
    static let maximumPinnedCount = 4
}

enum FavoriteEntryKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case link
    case folder
    case website
    case file

    static let selectableCases: [FavoriteEntryKind] = [.link, .folder]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link, .website, .file: return "链接"
        case .folder: return "文件夹"
        }
    }

    var symbol: String {
        switch self {
        case .link, .website, .file: return "globe"
        case .folder: return "folder.fill"
        }
    }

    var isFolder: Bool {
        self == .folder
    }
}

struct FavoriteEntry: Identifiable, Equatable, Codable, Hashable {
    let id: UUID
    var alias: String
    var target: String
    var kind: FavoriteEntryKind
    var groupName: String
    var parentFolderID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        alias: String,
        target: String,
        kind: FavoriteEntryKind,
        groupName: String = "",
        parentFolderID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.alias = alias
        self.target = target
        self.kind = kind
        self.groupName = groupName
        self.parentFolderID = parentFolderID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var groupTitle: String {
        let clean = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "未分组" : clean
    }

    var displayTarget: String {
        switch kind {
        case .folder:
            return "文件夹"
        case .link, .website:
            return target.isEmpty ? "链接" : target
        case .file:
            return (target as NSString).abbreviatingWithTildeInPath
        }
    }

    var isFolder: Bool {
        kind.isFolder
    }
}

struct FavoriteTreeNode: Identifiable, Equatable {
    let entry: FavoriteEntry
    let children: [FavoriteTreeNode]

    var id: FavoriteEntry.ID { entry.id }
}

enum HotkeyAction: String, CaseIterable, Identifiable, Hashable {
    case clipboardHistory
    case screenshot
    case pomodoroToggle
    case togglePetWindow
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboardHistory: return "剪贴板历史"
        case .screenshot: return "区域截图"
        case .pomodoroToggle: return "番茄钟开始/暂停"
        case .togglePetWindow: return "显示/隐藏小狗"
        case .favorites: return "常用入口"
        }
    }

    var subtitle: String {
        switch self {
        case .clipboardHistory: return "打开最近复制的文本和图片"
        case .screenshot: return "框选区域并复制到剪贴板"
        case .pomodoroToggle: return "切换当前番茄钟状态"
        case .togglePetWindow: return "快速收起或唤回桌面小狗"
        case .favorites: return "打开书签和常用入口面板"
        }
    }

    var symbol: String {
        switch self {
        case .clipboardHistory: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
        case .pomodoroToggle: return "timer"
        case .togglePetWindow: return "pawprint.fill"
        case .favorites: return "star.fill"
        }
    }

    var hotkeyID: UInt32 {
        switch self {
        case .clipboardHistory: return 1
        case .screenshot: return 2
        case .pomodoroToggle: return 3
        case .togglePetWindow: return 4
        case .favorites: return 5
        }
    }

    var defaultHotkey: WorkdogHotkey {
        switch self {
        case .clipboardHistory:
            return WorkdogHotkey(keyCode: 9, carbonModifiers: UInt32(cmdKey | optionKey), keyEquivalent: "V")
        case .screenshot:
            return WorkdogHotkey(keyCode: 1, carbonModifiers: UInt32(cmdKey | optionKey), keyEquivalent: "S")
        case .pomodoroToggle:
            return WorkdogHotkey(keyCode: 35, carbonModifiers: UInt32(cmdKey | optionKey), keyEquivalent: "P")
        case .togglePetWindow:
            return WorkdogHotkey(keyCode: 11, carbonModifiers: UInt32(cmdKey | optionKey), keyEquivalent: "B")
        case .favorites:
            return WorkdogHotkey(keyCode: 3, carbonModifiers: UInt32(cmdKey | optionKey), keyEquivalent: "F")
        }
    }

    var legacyDefaultHotkeys: [WorkdogHotkey] {
        switch self {
        case .togglePetWindow:
            return [WorkdogHotkey(keyCode: 2, carbonModifiers: UInt32(cmdKey | optionKey), keyEquivalent: "D")]
        default:
            return []
        }
    }
}

struct WorkdogHotkey: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String

    var displayText: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 {
            parts += "⌃"
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            parts += "⌥"
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            parts += "⇧"
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            parts += "⌘"
        }
        return parts + keyEquivalent
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyEquivalent: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyEquivalent = keyEquivalent
    }

    init?(event: NSEvent) {
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        let requiredModifiers = UInt32(controlKey | optionKey | cmdKey)
        guard modifiers & requiredModifiers != 0 else { return nil }

        let keyCode = UInt32(event.keyCode)
        guard keyCode != 53, keyCode != 51, keyCode != 117 else { return nil }

        let keyEquivalent = Self.keyEquivalent(
            for: event.keyCode,
            characters: event.charactersIgnoringModifiers
        )
        guard !keyEquivalent.isEmpty else { return nil }

        self.keyCode = keyCode
        carbonModifiers = modifiers
        self.keyEquivalent = keyEquivalent
    }

    private static func keyEquivalent(for keyCode: UInt16, characters: String?) -> String {
        if let special = specialKeyNames[keyCode] {
            return special
        }

        let clean = (characters ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return keyCode == 49 ? "Space" : ""
        }

        return clean.uppercased()
    }

    private static let specialKeyNames: [UInt16: String] = [
        36: "↩",
        48: "⇥",
        49: "Space",
        76: "⌤",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        118: "Home",
        119: "End",
        120: "F2",
        121: "PageDown",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑",
    ]
}

struct ClipboardHistoryItem: Identifiable, Equatable, Codable {
    let id: UUID
    let kind: ClipboardHistoryKind
    let text: String?
    let imageFilename: String?
    let imagePixelWidth: Int?
    let imagePixelHeight: Int?
    let filePaths: [String]?
    let fileNames: [String]?
    let fileTypeDescription: String?
    let fileTotalByteCount: Int64?
    let contentHash: String?
    var isPinned: Bool
    var pinnedAt: Date?
    let copiedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        copiedAt: Date = Date(),
        isPinned: Bool = false,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        kind = .text
        self.text = text
        imageFilename = nil
        imagePixelWidth = nil
        imagePixelHeight = nil
        filePaths = nil
        fileNames = nil
        fileTypeDescription = nil
        fileTotalByteCount = nil
        contentHash = nil
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.copiedAt = copiedAt
    }

    init(
        id: UUID = UUID(),
        imageFilename: String,
        imagePixelWidth: Int,
        imagePixelHeight: Int,
        contentHash: String,
        copiedAt: Date = Date(),
        isPinned: Bool = false,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        kind = .image
        text = nil
        self.imageFilename = imageFilename
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        filePaths = nil
        fileNames = nil
        fileTypeDescription = nil
        fileTotalByteCount = nil
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.copiedAt = copiedAt
    }

    init(
        id: UUID = UUID(),
        filePaths: [String],
        fileNames: [String],
        fileTypeDescription: String,
        fileTotalByteCount: Int64?,
        contentHash: String,
        copiedAt: Date = Date(),
        isPinned: Bool = false,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        kind = .file
        text = nil
        imageFilename = nil
        imagePixelWidth = nil
        imagePixelHeight = nil
        self.filePaths = filePaths
        self.fileNames = fileNames
        self.fileTypeDescription = fileTypeDescription
        self.fileTotalByteCount = fileTotalByteCount
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.copiedAt = copiedAt
    }

    var preview: String {
        switch kind {
        case .text:
            guard let text else { return "" }
            let collapsed = text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !collapsed.isEmpty else { return text }
            return collapsed
        case .image:
            return "图片"
        case .file:
            let paths = filePaths ?? []
            guard let firstPath = paths.first else { return "文件" }
            guard paths.count > 1 else { return firstPath }
            let visiblePaths = paths.prefix(3).joined(separator: "\n")
            return "\(visiblePaths)\n等 \(paths.count) 个文件"
        }
    }

    var detailText: String {
        switch kind {
        case .text:
            return "\(text?.count ?? 0) 字"
        case .image:
            guard let imagePixelWidth, let imagePixelHeight else { return "图片" }
            return "\(imagePixelWidth)x\(imagePixelHeight)"
        case .file:
            let count = filePaths?.count ?? 0
            let countText = count > 1 ? "\(count) 个文件" : (fileTypeDescription ?? "文件")
            guard let fileTotalByteCount, fileTotalByteCount > 0 else {
                return countText
            }
            let sizeText = ByteCountFormatter.string(fromByteCount: fileTotalByteCount, countStyle: .file)
            return "\(countText) · \(sizeText)"
        }
    }

    var fileCountText: String {
        let count = filePaths?.count ?? 0
        return count > 1 ? "\(count) 个文件" : (fileTypeDescription ?? "文件")
    }

    var copiedAtText: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: copiedAt)
    }

    var clipboardSortDate: Date {
        isPinned ? (pinnedAt ?? copiedAt) : copiedAt
    }

    func matchesSearchQuery(_ query: String) -> Bool {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return true }

        let fields = searchableFields.filter { !$0.isEmpty }
        return terms.allSatisfy { term in
            fields.contains { field in
                field.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private var searchableFields: [String] {
        let pinFields = isPinned ? ["置顶", "固定", "图钉"] : []

        switch kind {
        case .text:
            return pinFields + [
                "文本",
                "文本片段",
                text ?? "",
                preview,
                detailText,
            ]
        case .image:
            return pinFields + [
                "图片",
                "图像",
                detailText,
                imagePixelWidth.map(String.init) ?? "",
                imagePixelHeight.map(String.init) ?? "",
            ]
        case .file:
            return pinFields + [
                "文件",
                fileTypeDescription ?? "",
                fileCountText,
                detailText,
                preview,
            ] + (fileNames ?? []) + (filePaths ?? [])
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case imageFilename
        case imagePixelWidth
        case imagePixelHeight
        case filePaths
        case fileNames
        case fileTypeDescription
        case fileTotalByteCount
        case contentHash
        case isPinned
        case pinnedAt
        case copiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(ClipboardHistoryKind.self, forKey: .kind) ?? .text
        text = try container.decodeIfPresent(String.self, forKey: .text)
        imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        imagePixelWidth = try container.decodeIfPresent(Int.self, forKey: .imagePixelWidth)
        imagePixelHeight = try container.decodeIfPresent(Int.self, forKey: .imagePixelHeight)
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths)
        fileNames = try container.decodeIfPresent([String].self, forKey: .fileNames)
        fileTypeDescription = try container.decodeIfPresent(String.self, forKey: .fileTypeDescription)
        fileTotalByteCount = try container.decodeIfPresent(Int64.self, forKey: .fileTotalByteCount)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
    }
}

enum ReminderKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case water
    case rest
    case cheer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: return "喝水"
        case .rest: return "休息"
        case .cheer: return "打气"
        }
    }

    var symbol: String {
        switch self {
        case .water: return "drop.fill"
        case .rest: return "bed.double.fill"
        case .cheer: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .water: return Color(red: 0.24, green: 0.55, blue: 0.96)
        case .rest: return Color(red: 0.55, green: 0.36, blue: 0.95)
        case .cheer: return Color(red: 0.96, green: 0.55, blue: 0.20)
        }
    }

    var mood: DogMood {
        switch self {
        case .water: return .happy
        case .rest: return .idle
        case .cheer: return .energized
        }
    }
}

enum ReminderPreset: String, CaseIterable, Identifiable {
    case gentle
    case standard
    case active
    case custom

    var id: String { rawValue }

    static let selectableCases: [ReminderPreset] = [.gentle, .standard, .active]

    var title: String {
        switch self {
        case .gentle: return "轻柔"
        case .standard: return "标准"
        case .active: return "积极"
        case .custom: return "自定"
        }
    }

    var intervals: (water: Double, rest: Double, cheer: Double)? {
        switch self {
        case .gentle:
            return (water: 60, rest: 120, cheer: 180)
        case .standard:
            return (water: 45, rest: 90, cheer: 120)
        case .active:
            return (water: 30, rest: 60, cheer: 90)
        case .custom:
            return nil
        }
    }

    static func matching(water: Double, rest: Double, cheer: Double) -> ReminderPreset {
        for preset in selectableCases {
            guard let intervals = preset.intervals else { continue }
            if Int(water.rounded()) == Int(intervals.water),
               Int(rest.rounded()) == Int(intervals.rest),
               Int(cheer.rounded()) == Int(intervals.cheer) {
                return preset
            }
        }
        return .custom
    }
}

enum DogMood: String, CaseIterable, Identifiable {
    case idle
    case happy
    case energized
    case proud

    var id: String { rawValue }
}

enum PomodoroMode: String, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "专注"
        case .shortBreak: return "短休"
        case .longBreak: return "长休"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "timer"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "moon.zzz.fill"
        }
    }

    var tint: Color {
        switch self {
        case .focus: return Color(red: 0.22, green: 0.48, blue: 0.92)
        case .shortBreak: return Color(red: 0.22, green: 0.68, blue: 0.54)
        case .longBreak: return Color(red: 0.52, green: 0.40, blue: 0.88)
        }
    }

    var defaultMinutes: Double {
        switch self {
        case .focus: return 25
        case .shortBreak: return 5
        case .longBreak: return 15
        }
    }
}

enum PomodoroState: String {
    case idle
    case running
    case paused
}

enum DogShape: String, CaseIterable, Identifiable {
    case round
    case fluffy
    case sleek
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .round: return "圆润"
        case .fluffy: return "蓬松"
        case .sleek: return "利落"
        case .compact: return "紧凑"
        }
    }

    var metrics: DogMetrics {
        switch self {
        case .round:
            return DogMetrics(bodyWidth: 120, bodyHeight: 90, bodyCornerRadius: 40, headSize: 96, earWidth: 22, earHeight: 46, legHeight: 20, tailLength: 30, headYOffset: -40, bodyYOffset: 30)
        case .fluffy:
            return DogMetrics(bodyWidth: 128, bodyHeight: 98, bodyCornerRadius: 30, headSize: 100, earWidth: 24, earHeight: 52, legHeight: 22, tailLength: 32, headYOffset: -44, bodyYOffset: 34)
        case .sleek:
            return DogMetrics(bodyWidth: 112, bodyHeight: 80, bodyCornerRadius: 22, headSize: 88, earWidth: 20, earHeight: 40, legHeight: 18, tailLength: 34, headYOffset: -34, bodyYOffset: 28)
        case .compact:
            return DogMetrics(bodyWidth: 106, bodyHeight: 84, bodyCornerRadius: 26, headSize: 86, earWidth: 20, earHeight: 38, legHeight: 18, tailLength: 26, headYOffset: -34, bodyYOffset: 30)
        }
    }
}

struct DogMetrics {
    let bodyWidth: CGFloat
    let bodyHeight: CGFloat
    let bodyCornerRadius: CGFloat
    let headSize: CGFloat
    let earWidth: CGFloat
    let earHeight: CGFloat
    let legHeight: CGFloat
    let tailLength: CGFloat
    let headYOffset: CGFloat
    let bodyYOffset: CGFloat
}

enum DogCoat: String, CaseIterable, Identifiable {
    case golden
    case cream
    case cocoa
    case charcoal
    case sky
    case mint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .golden: return "金黄"
        case .cream: return "奶油"
        case .cocoa: return "可可"
        case .charcoal: return "灰黑"
        case .sky: return "天蓝"
        case .mint: return "薄荷"
        }
    }

    var body: Color {
        switch self {
        case .golden: return Color(red: 0.93, green: 0.72, blue: 0.36)
        case .cream: return Color(red: 0.98, green: 0.90, blue: 0.72)
        case .cocoa: return Color(red: 0.66, green: 0.43, blue: 0.23)
        case .charcoal: return Color(red: 0.28, green: 0.30, blue: 0.34)
        case .sky: return Color(red: 0.56, green: 0.77, blue: 0.96)
        case .mint: return Color(red: 0.56, green: 0.86, blue: 0.74)
        }
    }

    var ear: Color {
        switch self {
        case .golden: return Color(red: 0.82, green: 0.58, blue: 0.24)
        case .cream: return Color(red: 0.88, green: 0.77, blue: 0.56)
        case .cocoa: return Color(red: 0.50, green: 0.30, blue: 0.16)
        case .charcoal: return Color(red: 0.18, green: 0.20, blue: 0.24)
        case .sky: return Color(red: 0.34, green: 0.58, blue: 0.88)
        case .mint: return Color(red: 0.30, green: 0.72, blue: 0.58)
        }
    }

    var accent: Color {
        switch self {
        case .golden: return Color(red: 0.97, green: 0.88, blue: 0.48)
        case .cream: return Color(red: 0.99, green: 0.95, blue: 0.82)
        case .cocoa: return Color(red: 0.78, green: 0.60, blue: 0.41)
        case .charcoal: return Color(red: 0.58, green: 0.62, blue: 0.70)
        case .sky: return Color(red: 0.84, green: 0.93, blue: 1.0)
        case .mint: return Color(red: 0.85, green: 0.98, blue: 0.92)
        }
    }

    var outline: Color {
        switch self {
        case .golden: return Color(red: 0.72, green: 0.48, blue: 0.18)
        case .cream: return Color(red: 0.82, green: 0.70, blue: 0.48)
        case .cocoa: return Color(red: 0.38, green: 0.24, blue: 0.14)
        case .charcoal: return Color(red: 0.12, green: 0.14, blue: 0.18)
        case .sky: return Color(red: 0.22, green: 0.46, blue: 0.72)
        case .mint: return Color(red: 0.22, green: 0.58, blue: 0.46)
        }
    }

    // Lighter shade for gradient highlights
    var highlight: Color {
        switch self {
        case .golden: return Color(red: 1.0, green: 0.90, blue: 0.60)
        case .cream: return Color(red: 1.0, green: 0.97, blue: 0.90)
        case .cocoa: return Color(red: 0.82, green: 0.62, blue: 0.42)
        case .charcoal: return Color(red: 0.52, green: 0.56, blue: 0.64)
        case .sky: return Color(red: 0.82, green: 0.94, blue: 1.0)
        case .mint: return Color(red: 0.82, green: 1.0, blue: 0.94)
        }
    }

    // Darker shade for gradient shadows
    var shadow: Color {
        switch self {
        case .golden: return Color(red: 0.72, green: 0.50, blue: 0.18)
        case .cream: return Color(red: 0.82, green: 0.70, blue: 0.50)
        case .cocoa: return Color(red: 0.42, green: 0.26, blue: 0.12)
        case .charcoal: return Color(red: 0.12, green: 0.14, blue: 0.18)
        case .sky: return Color(red: 0.30, green: 0.52, blue: 0.80)
        case .mint: return Color(red: 0.26, green: 0.62, blue: 0.48)
        }
    }

    // Belly / inner area soft color
    var belly: Color {
        switch self {
        case .golden: return Color(red: 1.0, green: 0.92, blue: 0.70)
        case .cream: return Color(red: 1.0, green: 0.98, blue: 0.92)
        case .cocoa: return Color(red: 0.88, green: 0.72, blue: 0.55)
        case .charcoal: return Color(red: 0.48, green: 0.52, blue: 0.60)
        case .sky: return Color(red: 0.88, green: 0.96, blue: 1.0)
        case .mint: return Color(red: 0.88, green: 1.0, blue: 0.96)
        }
    }
}

struct ReminderPhraseLines: Codable, Equatable {
    var water: [String]
    var rest: [String]
    var cheer: [String]

    init(water: [String], rest: [String], cheer: [String]) {
        self.water = water
        self.rest = rest
        self.cheer = cheer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        water = (try? container.decodeIfPresent([String].self, forKey: .water)) ?? []
        rest = (try? container.decodeIfPresent([String].self, forKey: .rest)) ?? []
        cheer = (try? container.decodeIfPresent([String].self, forKey: .cheer)) ?? []
    }

    func lines(for kind: ReminderKind) -> [String] {
        switch kind {
        case .water:
            return water
        case .rest:
            return rest
        case .cheer:
            return cheer
        }
    }

    mutating func setLines(_ lines: [String], for kind: ReminderKind) {
        switch kind {
        case .water:
            water = lines
        case .rest:
            rest = lines
        case .cheer:
            cheer = lines
        }
    }
}

struct PomodoroCompletionPhraseLines: Codable, Equatable {
    var focus: [String]
    var focusMilestone: [String]
    var shortBreak: [String]
    var longBreak: [String]

    init(focus: [String], focusMilestone: [String], shortBreak: [String], longBreak: [String]) {
        self.focus = focus
        self.focusMilestone = focusMilestone
        self.shortBreak = shortBreak
        self.longBreak = longBreak
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focus = (try? container.decodeIfPresent([String].self, forKey: .focus)) ?? []
        focusMilestone = (try? container.decodeIfPresent([String].self, forKey: .focusMilestone)) ?? []
        shortBreak = (try? container.decodeIfPresent([String].self, forKey: .shortBreak)) ?? []
        longBreak = (try? container.decodeIfPresent([String].self, forKey: .longBreak)) ?? []
    }

    func lines(for mode: PomodoroMode, completedFocusCount: Int, longBreakEvery: Int = 4) -> [String] {
        switch mode {
        case .focus:
            let milestoneInterval = max(1, longBreakEvery)
            if completedFocusCount > 0, completedFocusCount % milestoneInterval == 0 {
                return focusMilestone
            }
            return focus
        case .shortBreak:
            return shortBreak
        case .longBreak:
            return longBreak
        }
    }
}

struct WorkdogPhrasePack: Codable, Equatable {
    var startup: [String]
    var reminders: ReminderPhraseLines
    var records: ReminderPhraseLines
    var petting: [String]
    var pomodoroFocusStart: [String]
    var pomodoroBreakStart: [String]
    var pomodoroCompletion: PomodoroCompletionPhraseLines

    init(
        startup: [String],
        reminders: ReminderPhraseLines,
        records: ReminderPhraseLines,
        petting: [String],
        pomodoroFocusStart: [String],
        pomodoroBreakStart: [String],
        pomodoroCompletion: PomodoroCompletionPhraseLines
    ) {
        self.startup = startup
        self.reminders = reminders
        self.records = records
        self.petting = petting
        self.pomodoroFocusStart = pomodoroFocusStart
        self.pomodoroBreakStart = pomodoroBreakStart
        self.pomodoroCompletion = pomodoroCompletion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaultPack
        startup = (try? container.decodeIfPresent([String].self, forKey: .startup)) ?? fallback.startup
        reminders = (try? container.decodeIfPresent(ReminderPhraseLines.self, forKey: .reminders)) ?? fallback.reminders
        records = (try? container.decodeIfPresent(ReminderPhraseLines.self, forKey: .records)) ?? fallback.records
        petting = (try? container.decodeIfPresent([String].self, forKey: .petting)) ?? fallback.petting
        pomodoroFocusStart = (try? container.decodeIfPresent([String].self, forKey: .pomodoroFocusStart)) ?? fallback.pomodoroFocusStart
        pomodoroBreakStart = (try? container.decodeIfPresent([String].self, forKey: .pomodoroBreakStart)) ?? fallback.pomodoroBreakStart
        pomodoroCompletion = (try? container.decodeIfPresent(PomodoroCompletionPhraseLines.self, forKey: .pomodoroCompletion)) ?? fallback.pomodoroCompletion
    }

    static let defaultPack = WorkdogPhrasePack(
        startup: [
            "我是你的快乐小狗。",
            "{name}，我会在这里陪着你。"
        ],
        reminders: ReminderPhraseLines(
            water: [
                "{name}，先喝两口水，脑子会更顺。",
                "补点水再继续，状态会更稳。",
                "{name}，今天的第一步是照顾好自己。"
            ],
            rest: [
                "站起来走两步，肩膀会感谢你。",
                "给眼睛放个小假，回来更轻松。",
                "{name}，现在可以歇一会儿。"
            ],
            cheer: [
                "今天已经很能打了，继续往前走。",
                "这关不难，拆开来就行。",
                "{name}，你已经推进很多了。"
            ]
        ),
        records: ReminderPhraseLines(
            water: [
                "{name}，这次喝水我记下了，今天第 {count} 次。",
                "好，补水完成。今天已经记录 {count} 次。",
                "收到，水分到账，今天第 {count} 次。"
            ],
            rest: [
                "{name}，这次休息我记下了，今天第 {count} 次。",
                "休息不是偷懒，今天已经记录 {count} 次。",
                "好，给自己留了空隙，今天第 {count} 次休息。"
            ],
            cheer: [
                "这一下打气我记下了，今天第 {count} 次。",
                "{name}，给自己加一格能量，今天第 {count} 次。",
                "状态补给完成，今天第 {count} 次打气。"
            ]
        ),
        petting: [
            "摸摸收到，我会乖乖陪着你。",
            "{name}，我在这里，慢慢来就好。",
            "嘿嘿，今天也一起稳稳推进。",
            "尾巴摇起来了，继续陪你。"
        ],
        pomodoroFocusStart: [
            "进入专注时间，我帮你守着节奏。"
        ],
        pomodoroBreakStart: [
            "休息时间到，先把自己放轻一点。"
        ],
        pomodoroCompletion: PomodoroCompletionPhraseLines(
            focus: [
                "{name}，一个番茄钟完成了，先离开屏幕几分钟。"
            ],
            focusMilestone: [
                "{name}，第 {completedFocusCount} 个专注完成，去认真休息一会儿。"
            ],
            shortBreak: [
                "短休结束，回来慢慢进入下一段专注。"
            ],
            longBreak: [
                "长休结束，状态回血了，可以继续推进。"
            ]
        )
    )

    static func editableLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum ReminderPhraseBook {
    static func message(for kind: ReminderKind, name: String, pack: WorkdogPhrasePack = .defaultPack) -> String {
        render(randomLine(from: pack.reminders.lines(for: kind), fallback: WorkdogPhrasePack.defaultPack.reminders.lines(for: kind)), name: name)
    }

    static func startupLine(name: String, pack: WorkdogPhrasePack = .defaultPack) -> String {
        render(randomLine(from: pack.startup, fallback: WorkdogPhrasePack.defaultPack.startup), name: name)
    }

    static func recordLine(for kind: ReminderKind, count: Int, name: String, pack: WorkdogPhrasePack = .defaultPack) -> String {
        render(
            randomLine(from: pack.records.lines(for: kind), fallback: WorkdogPhrasePack.defaultPack.records.lines(for: kind)),
            name: name,
            count: count
        )
    }

    static func pettingLine(name: String, pack: WorkdogPhrasePack = .defaultPack) -> String {
        render(randomLine(from: pack.petting, fallback: WorkdogPhrasePack.defaultPack.petting), name: name)
    }

    static func pomodoroStart(mode: PomodoroMode, name: String, pack: WorkdogPhrasePack = .defaultPack) -> String {
        let lines = mode == .focus ? pack.pomodoroFocusStart : pack.pomodoroBreakStart
        let fallback = mode == .focus ? WorkdogPhrasePack.defaultPack.pomodoroFocusStart : WorkdogPhrasePack.defaultPack.pomodoroBreakStart
        return render(randomLine(from: lines, fallback: fallback), name: name)
    }

    static func pomodoroCompletion(
        mode: PomodoroMode,
        completedFocusCount: Int,
        longBreakEvery: Int = 4,
        name: String,
        pack: WorkdogPhrasePack = .defaultPack
    ) -> String {
        render(
            randomLine(
                from: pack.pomodoroCompletion.lines(
                    for: mode,
                    completedFocusCount: completedFocusCount,
                    longBreakEvery: longBreakEvery
                ),
                fallback: WorkdogPhrasePack.defaultPack.pomodoroCompletion.lines(
                    for: mode,
                    completedFocusCount: completedFocusCount,
                    longBreakEvery: longBreakEvery
                )
            ),
            name: name,
            completedFocusCount: completedFocusCount
        )
    }

    private static func randomLine(from lines: [String], fallback: [String]) -> String {
        let candidates = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let line = candidates.randomElement() {
            return line
        }
        return fallback
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .randomElement() ?? ""
    }

    private static func render(_ template: String, name: String, count: Int? = nil, completedFocusCount: Int? = nil) -> String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = cleanName.isEmpty ? "你" : cleanName
        var result = template.replacingOccurrences(of: "{name}", with: prefix)
        if let count {
            result = result.replacingOccurrences(of: "{count}", with: "\(count)")
        }
        if let completedFocusCount {
            result = result.replacingOccurrences(of: "{completedFocusCount}", with: "\(completedFocusCount)")
        }
        return result
    }
}
