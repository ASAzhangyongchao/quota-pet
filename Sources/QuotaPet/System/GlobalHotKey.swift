import AppKit
import Carbon
import Foundation

struct HotKeyShortcut: Codable, Equatable {
    static let commandModifier: UInt32 = UInt32(cmdKey)
    static let optionModifier: UInt32 = UInt32(optionKey)
    static let controlModifier: UInt32 = UInt32(controlKey)
    static let shiftModifier: UInt32 = UInt32(shiftKey)
    static let optionCommandU = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_U), carbonModifiers: commandModifier | optionModifier)

    let keyCode: UInt32
    let carbonModifiers: UInt32

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & Self.controlModifier != 0 { parts.append("⌃") }
        if carbonModifiers & Self.optionModifier != 0 { parts.append("⌥") }
        if carbonModifiers & Self.shiftModifier != 0 { parts.append("⇧") }
        if carbonModifiers & Self.commandModifier != 0 { parts.append("⌘") }
        parts.append(Self.keyLabel(for: keyCode))
        return parts.joined()
    }

    /// Requires at least ⌘ / ⌥ / ⌃ so bare letters cannot steal typing focus system-wide.
    static func fromKeyEvent(_ event: NSEvent) -> HotKeyShortcut? {
        guard event.type == .keyDown else { return nil }
        if event.keyCode == UInt16(kVK_Escape) { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= controlModifier }
        if flags.contains(.option) { carbon |= optionModifier }
        if flags.contains(.shift) { carbon |= shiftModifier }
        if flags.contains(.command) { carbon |= commandModifier }
        let hasPrimaryModifier = carbon & (commandModifier | optionModifier | controlModifier) != 0
        guard hasPrimaryModifier else { return nil }
        let keyCode = UInt32(event.keyCode)
        guard keyCode <= 0x7F else { return nil }
        // Ignore modifier-only presses (no primary key yet).
        guard ![
            UInt32(kVK_Command), UInt32(kVK_Shift), UInt32(kVK_Option), UInt32(kVK_Control),
            UInt32(kVK_RightCommand), UInt32(kVK_RightShift), UInt32(kVK_RightOption), UInt32(kVK_RightControl),
            UInt32(kVK_Function),
        ].contains(keyCode) else { return nil }
        return HotKeyShortcut(keyCode: keyCode, carbonModifiers: carbon)
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key\(keyCode)"
        }
    }
}

enum GlobalHotKeyError: Error, Equatable { case occupied, registrationFailed }

protocol GlobalHotKeyBackend: AnyObject {
    func installHandler(_ callback: @escaping () -> Void) -> Result<Int, GlobalHotKeyError>
    func removeHandler(_ handle: Int)
    func register(_ shortcut: HotKeyShortcut, handler: Int) -> Result<Int, GlobalHotKeyError>
    func unregister(_ handle: Int)
}

final class GlobalHotKey {
    private let backend: any GlobalHotKeyBackend
    private let callback: () -> Void
    private var handler: Int?
    private var registration: Int?

    init(backend: any GlobalHotKeyBackend = CarbonGlobalHotKeyBackend.shared, callback: @escaping () -> Void) {
        self.backend = backend
        self.callback = callback
    }

    deinit { invalidate() }

    func register(_ shortcut: HotKeyShortcut) -> Result<Void, GlobalHotKeyError> {
        if let registration { backend.unregister(registration); self.registration = nil }
        if handler == nil {
            switch backend.installHandler(callback) {
            case let .success(value): handler = value
            case let .failure(error): return .failure(error)
            }
        }
        guard let handler else { return .failure(.registrationFailed) }
        switch backend.register(shortcut, handler: handler) {
        case let .success(value): registration = value; return .success(())
        case let .failure(error): return .failure(error)
        }
    }

    func invalidate() {
        if let registration { backend.unregister(registration); self.registration = nil }
        if let handler { backend.removeHandler(handler); self.handler = nil }
    }
}

private final class CarbonGlobalHotKeyBackend: GlobalHotKeyBackend {
    static let shared = CarbonGlobalHotKeyBackend()
    private var nextID = 1
    private var callbacks: [Int: () -> Void] = [:]
    private var handlers: [Int: EventHandlerRef] = [:]
    private var registrations: [Int: EventHotKeyRef] = [:]

    func installHandler(_ callback: @escaping () -> Void) -> Result<Int, GlobalHotKeyError> {
        let identifier = nextID; nextID += 1
        callbacks[identifier] = callback
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr else { return noErr }
            let backend = Unmanaged<CarbonGlobalHotKeyBackend>.fromOpaque(userData).takeUnretainedValue()
            backend.callbacks[Int(hotKeyID.id)]?()
            return noErr
        }, 1, [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))], Unmanaged.passUnretained(self).toOpaque(), &ref)
        guard status == noErr, let ref else { callbacks.removeValue(forKey: identifier); return .failure(.registrationFailed) }
        handlers[identifier] = ref
        return .success(identifier)
    }

    func removeHandler(_ handle: Int) {
        if let ref = handlers.removeValue(forKey: handle) { RemoveEventHandler(ref) }
        callbacks.removeValue(forKey: handle)
    }

    func register(_ shortcut: HotKeyShortcut, handler: Int) -> Result<Int, GlobalHotKeyError> {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5150_6574), id: UInt32(handler))
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref { registrations[handler] = ref; return .success(handler) }
        return .failure(status == OSStatus(eventHotKeyExistsErr) ? .occupied : .registrationFailed)
    }

    func unregister(_ handle: Int) {
        if let ref = registrations.removeValue(forKey: handle) { UnregisterEventHotKey(ref) }
    }
}
