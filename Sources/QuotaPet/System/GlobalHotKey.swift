import Carbon
import Foundation

struct HotKeyShortcut: Codable, Equatable {
    static let commandModifier: UInt32 = UInt32(cmdKey)
    static let optionModifier: UInt32 = UInt32(optionKey)
    static let optionCommandU = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_U), carbonModifiers: commandModifier | optionModifier)
    let keyCode: UInt32
    let carbonModifiers: UInt32
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
