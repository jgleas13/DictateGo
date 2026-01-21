import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let appState = AppState.shared
            WindowCoordinator.shared.updateDockVisibility(appState: appState)
            if appState.shouldShowOnboarding {
                WindowCoordinator.shared.showOnboarding(appState: appState)
            } else {
                WindowCoordinator.shared.showSettings(appState: appState)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            let appState = AppState.shared
            if appState.shouldShowOnboarding {
                WindowCoordinator.shared.showOnboarding(appState: appState)
            } else {
                WindowCoordinator.shared.showSettings(appState: appState)
            }
        }
        return true
    }
}
