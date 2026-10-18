import Carbon.HIToolbox

/// A system-wide hotkey through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission (unlike an NSEvent global monitor).
final class Hotkey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private static var registry: [UInt32: Hotkey] = [:]
    private static var installed = false

    init(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        self.action = action
        Hotkey.installHandler()
        Hotkey.registry[id] = self
        let hkID = EventHotKeyID(signature: OSType(0x5A4F_4E45), id: id) // 'ZONE'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref)
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async { Hotkey.registry[hkID.id]?.action() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
