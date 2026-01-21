import AppKit
import SwiftUI

struct HotkeyCaptureSheet: View {
    let currentHotkey: Hotkey
    let allowsModifierOnly: Bool
    let onSave: (Hotkey) -> Void
    let onCancel: () -> Void

    @State private var pendingHotkey: Hotkey?
    @State private var showedInvalidHotkeyError = false
    @State private var showedFunctionKeyError = false

    private var canSave: Bool {
        guard let pendingHotkey else { return false }
        if allowsModifierOnly {
            return !pendingHotkey.modifierFlags.isEmpty
        }
        return !pendingHotkey.modifierFlags.isEmpty && pendingHotkey.keyCode != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Hotkey")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Press the key combination you want to use.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                Text(pendingHotkey?.displayString ?? currentHotkey.displayString)
                    .font(.system(size: 26, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .frame(height: 96)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(showedInvalidHotkeyError ? Color.orange : Color.clear, lineWidth: 1.5)
            )

            if showedInvalidHotkeyError {
                Text("Please include a modifier and a key (e.g. ⌥ Option + Space).")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
            }

            if showedFunctionKeyError {
                Text("The Function key is unavailable as it requires invasive system permissions.")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
            }

            Text("Current: \(currentHotkey.displayString)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Tip: Use a modifier + key (for example, ⌥ Option + Space).")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if canSave, let pendingHotkey {
                        onSave(pendingHotkey)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            pendingHotkey = currentHotkey
            showedInvalidHotkeyError = false
            showedFunctionKeyError = false
        }
        .overlay(
            HotkeyCaptureView(allowsModifierOnly: allowsModifierOnly, onFunctionKeyAttempt: {
                showedFunctionKeyError = true
                showedInvalidHotkeyError = false
            }) { hotkey in
                guard !hotkey.modifierFlags.isEmpty else {
                    showedInvalidHotkeyError = true
                    showedFunctionKeyError = false
                    return
                }
                pendingHotkey = hotkey
                showedInvalidHotkeyError = false
                showedFunctionKeyError = false
            }
            .frame(width: 0, height: 0)
        )
    }
}

struct HotkeyCaptureView: NSViewRepresentable {
    let allowsModifierOnly: Bool
    let onFunctionKeyAttempt: () -> Void
    let onCapture: (Hotkey) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.allowsModifierOnly = allowsModifierOnly
        view.onFunctionKeyAttempt = onFunctionKeyAttempt
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCaptureView: NSView {
    var onCapture: ((Hotkey) -> Void)?
    var onFunctionKeyAttempt: (() -> Void)?
    var allowsModifierOnly: Bool = false
    private var pendingModifiers: NSEvent.ModifierFlags = []
    private var didCaptureKeyDown = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.function) {
            onFunctionKeyAttempt?()
            return
        }
        didCaptureKeyDown = true
        pendingModifiers = []
        let hotkey = Hotkey.from(event: event)
        onCapture?(hotkey)
    }

    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.function) {
            onFunctionKeyAttempt?()
            pendingModifiers = []
            didCaptureKeyDown = false
            return
        }
        let flags = Hotkey.normalizedFlags(event.modifierFlags)
        if flags.isEmpty {
            if allowsModifierOnly && !didCaptureKeyDown && !pendingModifiers.isEmpty {
                let hotkey = Hotkey(keyCode: nil, modifiers: pendingModifiers.rawValue)
                onCapture?(hotkey)
            }
            pendingModifiers = []
            didCaptureKeyDown = false
            return
        }

        pendingModifiers = flags
    }
}
