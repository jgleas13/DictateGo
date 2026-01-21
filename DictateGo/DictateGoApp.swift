import SwiftUI

@main
struct DictateGoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra("DictateGo", systemImage: "waveform") {
            MenuBarContents()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
