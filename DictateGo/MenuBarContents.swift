import AppKit
import SwiftUI

struct MenuBarContents: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text("Status: \(appState.status.rawValue)")
            .disabled(true)
        Text("Hold \(appState.hotkey.displayString) to record")
            .disabled(true)
        Divider()
        Button("Settings…") {
            WindowCoordinator.shared.showSettings(appState: appState)
        }
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
