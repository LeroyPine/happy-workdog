import Foundation
import Testing
@testable import happy_workdog

struct HappyWorkdogTests {
    @Test func reminderMessagesAreNotEmpty() {
        let message = ReminderPhraseBook.message(for: .water, name: "阿旺")
        #expect(!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(message.contains("阿旺") || message.contains("你"))
    }

    @Test func manualRecordMessagesIncludeCount() {
        let message = ReminderPhraseBook.recordLine(for: .rest, count: 3, name: "阿旺")
        #expect(!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(message.contains("3"))
    }

    @Test func pettingMessagesAreNotEmpty() {
        let message = ReminderPhraseBook.pettingLine(name: "阿旺")
        #expect(!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func customReminderPhraseRendersPlaceholders() {
        var pack = WorkdogPhrasePack.defaultPack
        pack.records.setLines(["{name} 今天第 {count} 次休息"], for: .rest)

        let message = ReminderPhraseBook.recordLine(for: .rest, count: 3, name: "阿旺", pack: pack)
        #expect(message == "阿旺 今天第 3 次休息")
    }

    @Test func emptyCustomPhraseFallsBackToDefault() {
        var pack = WorkdogPhrasePack.defaultPack
        pack.reminders.setLines([], for: .water)

        let message = ReminderPhraseBook.message(for: .water, name: "阿旺", pack: pack)
        #expect(!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func phrasePackDecodeBackfillsMissingFields() throws {
        let data = Data(#"{"startup":["{name} 出发"]}"#.utf8)
        let pack = try JSONDecoder().decode(WorkdogPhrasePack.self, from: data)

        #expect(pack.startup == ["{name} 出发"])
        #expect(!pack.reminders.water.isEmpty)
        #expect(!pack.pomodoroCompletion.focus.isEmpty)
    }

    @Test func pomodoroMilestoneUsesConfiguredLongBreakInterval() {
        var pack = WorkdogPhrasePack.defaultPack
        pack.pomodoroCompletion.focus = ["普通 {completedFocusCount}"]
        pack.pomodoroCompletion.focusMilestone = ["长休 {completedFocusCount}"]

        let thirdFocus = ReminderPhraseBook.pomodoroCompletion(
            mode: .focus,
            completedFocusCount: 3,
            longBreakEvery: 3,
            name: "阿旺",
            pack: pack
        )
        let fourthFocus = ReminderPhraseBook.pomodoroCompletion(
            mode: .focus,
            completedFocusCount: 4,
            longBreakEvery: 3,
            name: "阿旺",
            pack: pack
        )

        #expect(thirdFocus == "长休 3")
        #expect(fourthFocus == "普通 4")
    }

    @Test func reminderPresetMatchesStandardIntervals() {
        let preset = ReminderPreset.matching(water: 45, rest: 90, cheer: 120)
        #expect(preset == .standard)
    }

    @Test func reminderPresetFallsBackToCustomIntervals() {
        let preset = ReminderPreset.matching(water: 47, rest: 90, cheer: 120)
        #expect(preset == .custom)
    }

    @Test func reminderCollisionOnlyDefersDifferentKinds() {
        let previousDate = Date()
        let now = previousDate.addingTimeInterval(60)

        #expect(!ReminderCoordinator.shouldDeferReminder(
            kind: .water,
            after: .water,
            previousDate: previousDate,
            now: now,
            minimumGap: 300
        ))
        #expect(ReminderCoordinator.shouldDeferReminder(
            kind: .rest,
            after: .water,
            previousDate: previousDate,
            now: now,
            minimumGap: 300
        ))
    }

    @Test func activityEventRoundTripsThroughJSON() throws {
        let event = WorkdogActivityEvent(kind: .manualRecord, reminder: .water, happenedAt: Date())
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(WorkdogActivityEvent.self, from: data)

        #expect(decoded == event)
    }

    @Test func compactJSONClipboardTextIsNotTreatedAsSensitive() {
        let text = #"{"userName":"AlexRider","count":18,"status":"ok!"}"#

        #expect(!WorkdogStore.looksSensitive(text))
    }

    @Test func compactJSONWithTokenFieldIsTreatedAsSensitive() {
        let text = #"{"access_token":"Abcd1234!"}"#

        #expect(WorkdogStore.looksSensitive(text))
    }

    @Test func opaqueTokenClipboardTextIsStillTreatedAsSensitive() {
        #expect(WorkdogStore.looksSensitive("Abcd1234!"))
    }

    @Test func customSensitiveKeywordMatchesClipboardText() {
        #expect(WorkdogStore.looksSensitive("internal-ticket", keywords: ["internal"], detectsComplexToken: false))
    }

    @Test func clipboardTextSearchMatchesCaseInsensitiveTerms() {
        let item = ClipboardHistoryItem(text: "Deploy Plan\nRelease Notes")

        #expect(item.matchesSearchQuery("deploy notes"))
        #expect(item.matchesSearchQuery("RELEASE"))
        #expect(!item.matchesSearchQuery("rollback"))
    }

    @Test func clipboardFileSearchMatchesNamesAndPaths() {
        let item = ClipboardHistoryItem(
            filePaths: ["/Users/alex/Projects/HappyWorkdog/README.md"],
            fileNames: ["README.md"],
            fileTypeDescription: "Markdown 文件",
            fileTotalByteCount: 1024,
            contentHash: "readme"
        )

        #expect(item.matchesSearchQuery("readme"))
        #expect(item.matchesSearchQuery("happyworkdog markdown"))
        #expect(!item.matchesSearchQuery("invoice"))
    }

    @Test func clipboardImageSearchMatchesKindAndDimensions() {
        let item = ClipboardHistoryItem(
            imageFilename: "preview.png",
            imagePixelWidth: 1280,
            imagePixelHeight: 720,
            contentHash: "preview"
        )

        #expect(item.matchesSearchQuery("图片"))
        #expect(item.matchesSearchQuery("1280"))
        #expect(!item.matchesSearchQuery("4096"))
    }

    @Test func clipboardSearchMatchesPinnedState() {
        let item = ClipboardHistoryItem(text: "Stable command", isPinned: true, pinnedAt: Date())

        #expect(item.matchesSearchQuery("置顶"))
        #expect(item.matchesSearchQuery("图钉"))
    }

    @Test func legacyClipboardHistoryDecodeBackfillsPinState() throws {
        let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","kind":"text","text":"legacy","copiedAt":0}"#.utf8)
        let item = try JSONDecoder().decode(ClipboardHistoryItem.self, from: data)

        #expect(!item.isPinned)
        #expect(item.pinnedAt == nil)
    }

    @Test func pinnedClipboardHistoryRoundTripsThroughJSON() throws {
        let pinnedAt = Date(timeIntervalSinceReferenceDate: 80)
        let item = ClipboardHistoryItem(text: "Pinned snippet", isPinned: true, pinnedAt: pinnedAt)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipboardHistoryItem.self, from: data)

        #expect(decoded.isPinned)
        #expect(decoded.pinnedAt == pinnedAt)
    }

    @Test func removedSensitiveKeywordDoesNotMatchJSONField() {
        let text = #"{"access_token":"Abcd1234!"}"#

        #expect(!WorkdogStore.looksSensitive(text, keywords: ["password"], detectsComplexToken: false))
    }

    @Test func complexTokenDetectionCanBeDisabled() {
        #expect(!WorkdogStore.looksSensitive("Abcd1234!", keywords: [], detectsComplexToken: false))
    }

    @Test func shapeMetricsStayPositive() {
        for shape in DogShape.allCases {
            let metrics = shape.metrics
            #expect(metrics.bodyWidth > 0)
            #expect(metrics.bodyHeight > 0)
            #expect(metrics.headSize > 0)
            #expect(metrics.tailLength > 0)
        }
    }

    @Test func coatIdentifiersAreUnique() {
        let rawValues = Set(DogCoat.allCases.map(\.rawValue))
        #expect(rawValues.count == DogCoat.allCases.count)
    }

    @Test func defaultPinnedQuickActionsStayCompact() {
        #expect(QuickAction.defaultPinned == [.pomodoro, .favorites, .clipboard, .screenshot])
        #expect(QuickAction.defaultPinned.count == QuickAction.maximumPinnedCount)
        #expect(!QuickAction.defaultPinned.contains(.settings))
    }

    @Test func legacyPinnedQuickActionVariantsAreRecognized() {
        #expect(QuickAction.legacyDefaultPinnedVariants.contains([.pomodoro, .clipboard, .screenshot]))
    }

    @Test func settingsLeadSecondaryQuickActionOrder() {
        #expect(QuickAction.secondaryDisplayOrder.first == .settings)
        #expect(Set(QuickAction.secondaryDisplayOrder) == Set(QuickAction.allCases))
    }
}
