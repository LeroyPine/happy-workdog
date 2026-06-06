import Carbon
import Foundation

final class HotkeyCoordinator {
    var onHotkeyPressed: (@MainActor (HotkeyAction) -> Void)?
    private(set) var failedActions: Set<HotkeyAction> = []

    private var registeredHotkeys: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    private let signature: OSType = 0x48574447

    @MainActor
    func reschedule(using store: WorkdogStore) {
        unregisterAll()
        failedActions = []

        guard store.hotkeysEnabled else { return }

        installHandlerIfNeeded()

        for action in HotkeyAction.allCases {
            guard let hotkey = store.hotkey(for: action) else { continue }
            register(hotkey, for: action)
        }
    }

    func stop() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        if status != noErr {
            eventHandler = nil
        }
    }

    private func register(_ hotkey: WorkdogHotkey, for action: HotkeyAction) {
        let hotkeyID = EventHotKeyID(signature: signature, id: action.hotkeyID)
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            failedActions.insert(action)
            return
        }

        registeredHotkeys[action] = hotkeyRef
    }

    private func unregisterAll() {
        for hotkeyRef in registeredHotkeys.values {
            UnregisterEventHotKey(hotkeyRef)
        }
        registeredHotkeys.removeAll()
    }

    fileprivate func handleHotkeyEvent(_ event: EventRef?) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr, hotkeyID.signature == signature else {
            return status
        }

        guard let action = HotkeyAction.allCases.first(where: { $0.hotkeyID == hotkeyID.id }) else {
            return OSStatus(eventNotHandledErr)
        }

        let handler = onHotkeyPressed
        Task { @MainActor in
            handler?(action)
        }
        return noErr
    }
}

private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let coordinator = Unmanaged<HotkeyCoordinator>.fromOpaque(userData).takeUnretainedValue()
    return coordinator.handleHotkeyEvent(event)
}
