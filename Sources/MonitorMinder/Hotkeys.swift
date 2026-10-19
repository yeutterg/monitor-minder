import Carbon.HIToolbox

/// Global ⌃⌥1…⌃⌥9 shortcuts through Carbon hot keys, which need no Accessibility access.
@MainActor
enum Hotkeys {
    private static var action: ((Int) -> Void)?
    private static var refs: [EventHotKeyRef?] = []

    static func register(_ action: @escaping (Int) -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let number = Int(id.id)
            DispatchQueue.main.async { MainActor.assumeIsolated { Hotkeys.action?(number) } }
            return noErr
        }, 1, &spec, nil, nil)

        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (i, key) in keys.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4D4D_6E64), id: UInt32(i + 1)) // 'MMnd'
            RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
            refs.append(ref)
        }
    }
}
