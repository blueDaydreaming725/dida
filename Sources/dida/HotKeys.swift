import Foundation
import Carbon.HIToolbox

/// Carbon 全局热键，无需辅助功能权限。
/// ⌥⌘M 静音 · ⌥⌘B 休息 · ⌥⌘P 面板
@MainActor
final class HotKeys {
    private static var callbacks: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef?] = []
    private static var handlerInstalled = false

    static func install(mute: @escaping () -> Void,
                        rest: @escaping () -> Void,
                        panel: @escaping () -> Void) {
        callbacks[1] = mute
        callbacks[2] = rest
        callbacks[3] = panel
        installHandlerIfNeeded()
        let signature = fourCC("dida")
        // kVK_ANSI_M = 46, kVK_ANSI_B = 11, kVK_ANSI_P = 35；cmdKey = 1<<8, optionKey = 1<<11
        for (id, keyCode) in [(UInt32(1), UInt32(46)), (UInt32(2), UInt32(11)), (UInt32(3), UInt32(35))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(keyCode,
                                             UInt32(cmdKey | optionKey),
                                             EventHotKeyID(signature: signature, id: id),
                                             GetApplicationEventTarget(),
                                             0,
                                             &ref)
            if status == noErr { refs.append(ref) }
        }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)
            if let callback = HotKeys.callbacks[hotKeyID.id] {
                DispatchQueue.main.async(execute: callback)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    private static func fourCC(_ s: String) -> OSType {
        var value: UInt32 = 0
        for byte in s.utf8.prefix(4) { value = value << 8 | UInt32(byte) }
        return OSType(value)
    }
}
