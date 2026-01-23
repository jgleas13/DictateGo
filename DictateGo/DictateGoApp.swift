import SwiftUI

@main
struct DictateGoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        MenuBarExtra("DictateGo", systemImage: "waveform") {
            MenuBarContents()
                .environmentObject(appState)
                .environmentObject(updaterController)
        }
        .menuBarExtraStyle(.menu)
    }
}
