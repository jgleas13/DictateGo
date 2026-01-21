import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private let state: OverlayState
    private var panel: NSPanel?

    init(state: OverlayState) {
        self.state = state
    }

    func show() {
        ensurePanel()
        updatePanelForCurrentState()
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func updatePosition() {
        positionPanel()
    }

    private func ensurePanel() {
        if panel != nil { return }

        let view = OverlayView()
            .environmentObject(state)
        let hosting = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.panel = panel
    }

    private func updatePanelForCurrentState() {
        guard let panel else { return }
        let size = desiredPanelSize(for: state.status)
        panel.setContentSize(size)
        panel.ignoresMouseEvents = state.status != .error && state.status != .airPodsWarning
    }

    private func positionPanel() {
        guard let panel else { return }
        guard let screen = targetScreen() else { return }

        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func targetScreen() -> NSScreen? {
        screenForMouse()
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func screenForMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private func desiredPanelSize(for status: OverlayStatus) -> CGSize {
        switch status {
        case .error:
            return CGSize(width: 440, height: 128)
        case .toast:
            return CGSize(width: 420, height: 52)
        case .airPodsWarning:
            return CGSize(width: 440, height: 128)
        case .transcribing, .recording, .speaking:
            return CGSize(width: 180, height: 44)
        case .hidden:
            return CGSize(width: 180, height: 44)
        }
    }
}
