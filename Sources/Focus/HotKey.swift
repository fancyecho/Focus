import Carbon

/// 全局快捷键（Carbon），可以分别收到按下和松开事件，用来实现“长按解除”。
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    init(keyCode: UInt32, modifiers: UInt32) {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) {
                    hotKey.onPress?()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    hotKey.onRelease?()
                }
            }
            return noErr
        }, eventTypes.count, &eventTypes, userData, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x4643_5553), id: 1) // 'FCUS'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
