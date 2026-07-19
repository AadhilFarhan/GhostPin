import Carbon.HIToolbox

/// Global hotkeys via Carbon RegisterEventHotKey — works system-wide without
/// Accessibility or Input Monitoring permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    func register(keyCode: Int, handler: @escaping () -> Void) {
        installIfNeeded()
        let id = nextID
        nextID += 1
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x47_48_50_4E), id: id) // 'GHPN'
        RegisterEventHotKey(UInt32(keyCode), UInt32(cmdKey | optionKey), hotKeyID,
                            GetEventDispatcherTarget(), 0, &ref)
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}

enum KeyCode {
    static let p = kVK_ANSI_P
    static let g = kVK_ANSI_G
    static let u = kVK_ANSI_U
}
