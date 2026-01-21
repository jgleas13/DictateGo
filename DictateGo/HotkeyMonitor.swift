import AppKit
import Carbon

final class HotkeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var modifierFlagsMonitor: Any?
    private var modifierKeyDownMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var currentHotkey: Hotkey = .default
    private var isPressed = false
    private var suppressModifierHold = false
    private var modifierHotkeyFlags: NSEvent.ModifierFlags = []
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?
    private let hotKeySignature: OSType = 0x56545458 // "VTTX"

    func start(hotkey: Hotkey, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        stop()
        currentHotkey = hotkey
        self.onPress = onPress
        self.onRelease = onRelease
        startMonitoring()
    }

    func updateHotkey(_ hotkey: Hotkey) {
        currentHotkey = hotkey
        restartMonitoring()
    }

    func restartMonitoring() {
        stop()
        startMonitoring()
    }

    func stop() {
        unregisterHotKey()
        stopModifierMonitoring()
        isPressed = false
    }

    private func startMonitoring() {
        guard onPress != nil || onRelease != nil else { return }
        if let keyCode = currentHotkey.keyCode {
            registerHotKey(keyCode: keyCode, modifiers: currentHotkey.modifierFlags)
        } else {
            startModifierMonitoring()
        }
    }

    private func registerHotKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        unregisterHotKey()

        let carbonModifiers = carbonFlags(from: modifiers)
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { return }

        let eventSpecs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            let monitor = Unmanaged<HotkeyMonitor>
                .fromOpaque(userData)
                .takeUnretainedValue()
            return monitor.handleHotKeyEvent(event)
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            eventSpecs.count,
            eventSpecs,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandler
        )
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
            self.hotKeyHandler = nil
        }
    }

    private func startModifierMonitoring() {
        stopModifierMonitoring()
        modifierHotkeyFlags = Hotkey.normalizedFlags(currentHotkey.modifierFlags)
        guard !modifierHotkeyFlags.isEmpty else { return }

        modifierFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierFlagsChanged(event)
        }
        modifierKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.handleNonModifierKeyDown()
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierFlagsChanged(event)
            return event
        }
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNonModifierKeyDown()
            return event
        }
    }

    private func stopModifierMonitoring() {
        if let modifierFlagsMonitor {
            NSEvent.removeMonitor(modifierFlagsMonitor)
            self.modifierFlagsMonitor = nil
        }
        if let modifierKeyDownMonitor {
            NSEvent.removeMonitor(modifierKeyDownMonitor)
            self.modifierKeyDownMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }
        resetModifierTapState()
    }

    private func handleModifierFlagsChanged(_ event: NSEvent) {
        if event.modifierFlags.contains(.function) {
            resetModifierTapState()
            return
        }
        let flags = Hotkey.normalizedFlags(event.modifierFlags)
        if flags.isEmpty {
            if isPressed {
                isPressed = false
                DispatchQueue.main.async { [weak self] in
                    self?.onRelease?()
                }
            }
            resetModifierTapState()
            return
        }

        if suppressModifierHold {
            return
        }

        if flags != modifierHotkeyFlags {
            if isPressed {
                isPressed = false
                DispatchQueue.main.async { [weak self] in
                    self?.onRelease?()
                }
            }
            resetModifierTapState()
            return
        }

        if !isPressed {
            isPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onPress?()
            }
        }
    }

    private func handleNonModifierKeyDown() {
        if isPressed {
            isPressed = false
            DispatchQueue.main.async { [weak self] in
                self?.onRelease?()
            }
        }
        suppressModifierHold = true
    }

    private func resetModifierTapState() {
        suppressModifierHold = false
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
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
        guard status == noErr, hotKeyID.signature == hotKeySignature else { return noErr }

        let kind = GetEventKind(event)
        if kind == UInt32(kEventHotKeyPressed) {
            if !isPressed {
                isPressed = true
                DispatchQueue.main.async { [weak self] in
                    self?.onPress?()
                }
            }
        } else if kind == UInt32(kEventHotKeyReleased) {
            if isPressed {
                isPressed = false
                DispatchQueue.main.async { [weak self] in
                    self?.onRelease?()
                }
            }
        }

        return noErr
    }

    private func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}

private extension NSEvent.ModifierFlags {
    func isSubset(of other: NSEvent.ModifierFlags) -> Bool {
        subtracting(other).isEmpty
    }
}
