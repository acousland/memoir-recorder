import Carbon
import Foundation

/// Carbon registers only this shortcut; it doesn't monitor the user's keyboard.
@MainActor
final class CaptureShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register() -> Bool {
        guard hotKey == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x4D4D4F52, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            Task { @MainActor in await AppModel.shared.toggleCapture() }
            return noErr
        }, 1, &eventType, nil, &handler)
        guard installed == noErr else { return false }
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x4D4D4F52, id: 1),
                                         GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
        }
        return result == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil
    }
}
