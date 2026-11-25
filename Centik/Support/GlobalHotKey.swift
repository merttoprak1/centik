import Carbon
import Foundation

/// Registers a system-wide keyboard shortcut using Carbon Events.
/// Works without Accessibility or Input Monitoring permissions.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    private static let signature: OSType = 0x434E544B // "CNTK"
    private static let hotKeyID: UInt32 = 1

    func register(combo: HotKeyCombo, onTrigger: @escaping () -> Void) {
        unregister()
        self.onTrigger = onTrigger

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == GlobalHotKey.signature,
                      hotKeyID.id == GlobalHotKey.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    instance.onTrigger?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard installStatus == noErr else { return }

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        onTrigger = nil
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}
