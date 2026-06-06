import Foundation
import AppKit
import UserNotifications

@MainActor
final class ReminderCoordinator: NSObject, UNUserNotificationCenterDelegate {
    var onReminder: ((ReminderKind) -> Void)?
    var onScheduleChanged: (() -> Void)?

    private let minimumReminderGap: TimeInterval = 5 * 60
    private var timers: [ReminderKind: Timer] = [:]
    private var intervals: [ReminderKind: TimeInterval] = [:]
    private var nextFireDates: [ReminderKind: Date] = [:]
    private var lastDeliveredAt: Date?
    private var lastDeliveredKind: ReminderKind?

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Happy Workdog notification permission failed: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Happy Workdog notification permission was not granted")
            }
        }
    }

    func reschedule(using store: WorkdogStore) {
        stop()

        guard store.remindersEnabled else {
            return
        }

        if store.waterEnabled {
            schedule(kind: .water, minutes: store.waterIntervalMinutes, delay: firstFireDelay(for: store.waterIntervalMinutes))
        }
        if store.restEnabled {
            schedule(kind: .rest, minutes: store.restIntervalMinutes, delay: firstFireDelay(for: store.restIntervalMinutes))
        }
        if store.cheerEnabled {
            schedule(kind: .cheer, minutes: store.cheerIntervalMinutes, delay: firstFireDelay(for: store.cheerIntervalMinutes))
        }
    }

    func reset(kind: ReminderKind, using store: WorkdogStore) {
        guard store.remindersEnabled, isEnabled(kind: kind, in: store) else { return }
        schedule(kind: kind, minutes: intervalMinutes(for: kind, in: store))
    }

    func nextFireDate(for kind: ReminderKind) -> Date? {
        nextFireDates[kind]
    }

    nonisolated func sendNotification(kind: ReminderKind, message: String) {
        sendNotification(
            title: "快乐小狗提醒你\(kind.title)",
            message: message,
            identifierPrefix: "happy-workdog-\(kind.rawValue)"
        )
    }

    nonisolated func sendNotification(title: String, message: String, identifierPrefix: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        // Attach the app icon so the notification always shows the dog image,
        // even if Notification Center's per-bundle icon cache is stale.
        if let attachment = Self.appIconAttachment() {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Happy Workdog notification failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static let iconLock = NSLock()
    nonisolated(unsafe) private static var cachedIconURL: URL?
    nonisolated(unsafe) private static var iconCachePrepared = false

    nonisolated private static func appIconAttachment() -> UNNotificationAttachment? {
        iconLock.lock()
        defer { iconLock.unlock() }

        if !iconCachePrepared {
            iconCachePrepared = true
            cachedIconURL = writeAppIconToTemp()
        }
        guard let url = cachedIconURL else { return nil }
        return try? UNNotificationAttachment(
            identifier: "happy-workdog-icon",
            url: url,
            options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false]
        )
    }

    nonisolated private static func writeAppIconToTemp() -> URL? {
        // NSImage(named:) and NSWorkspace are safe to call off the main thread for
        // resource lookup; we read the bytes once and reuse them for every reminder.
        let bundleIcon: NSImage? = {
            if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
                return NSImage(contentsOfFile: path)
            }
            return NSImage(named: NSImage.applicationIconName)
        }()

        guard let icon = bundleIcon,
              let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            NSLog("Happy Workdog notification icon: no icon image available")
            return nil
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HappyWorkdogNotifications", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("AppIcon.png")
        do {
            try png.write(to: target, options: .atomic)
            return target
        } catch {
            NSLog("Happy Workdog notification icon write failed: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func writeReminderLog(kind: ReminderKind, message: String) {
        writeLog(category: kind.rawValue, message: message)
    }

    func writeLog(category: String, message: String) {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("HappyWorkdog", isDirectory: true)
        let file = folder.appendingPathComponent("reminders.log")
        let line = "\(Date()) [\(category)] \(message)\n"

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: file, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("Happy Workdog reminder log failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
        intervals.removeAll()
        nextFireDates.removeAll()
        lastDeliveredAt = nil
        lastDeliveredKind = nil
        onScheduleChanged?()
    }

    private func schedule(kind: ReminderKind, minutes: Double, delay: TimeInterval? = nil) {
        timers[kind]?.invalidate()
        let interval = max(1, minutes) * 60
        let nextDelay = max(1, delay ?? interval)
        let fireDate = Date(timeIntervalSinceNow: nextDelay)
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimerFire(kind)
            }
        }
        timer.tolerance = min(nextDelay * 0.2, 120)
        RunLoop.main.add(timer, forMode: .common)
        timers[kind] = timer
        intervals[kind] = interval
        nextFireDates[kind] = fireDate
        onScheduleChanged?()
    }

    private func handleTimerFire(_ kind: ReminderKind) {
        timers[kind] = nil
        guard let interval = intervals[kind] else {
            nextFireDates[kind] = nil
            onScheduleChanged?()
            return
        }

        let now = Date()
        if let previousDate = lastDeliveredAt,
           Self.shouldDeferReminder(
            kind: kind,
            after: lastDeliveredKind,
            previousDate: previousDate,
            now: now,
            minimumGap: minimumReminderGap
        ) {
            let delay = minimumReminderGap - now.timeIntervalSince(previousDate)
            schedule(kind: kind, minutes: interval / 60, delay: delay)
            return
        }

        lastDeliveredAt = now
        lastDeliveredKind = kind
        onReminder?(kind)
        schedule(kind: kind, minutes: interval / 60)
    }

    nonisolated static func shouldDeferReminder(kind: ReminderKind, after previousKind: ReminderKind?, previousDate: Date?, now: Date, minimumGap: TimeInterval) -> Bool {
        guard let previousKind,
              let previousDate,
              previousKind != kind
        else { return false }

        return now.timeIntervalSince(previousDate) < minimumGap
    }

    private func firstFireDelay(for minutes: Double) -> TimeInterval {
        minutes <= 1 ? 5 : max(1, minutes) * 60
    }

    private func isEnabled(kind: ReminderKind, in store: WorkdogStore) -> Bool {
        switch kind {
        case .water:
            return store.waterEnabled
        case .rest:
            return store.restEnabled
        case .cheer:
            return store.cheerEnabled
        }
    }

    private func intervalMinutes(for kind: ReminderKind, in store: WorkdogStore) -> Double {
        switch kind {
        case .water:
            return store.waterIntervalMinutes
        case .rest:
            return store.restIntervalMinutes
        case .cheer:
            return store.cheerIntervalMinutes
        }
    }
}
