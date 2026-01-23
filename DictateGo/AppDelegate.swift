import AppKit
import Sparkle
import os

final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    private let logger = Logger(subsystem: "com.johngleason.DictateGo", category: "Sparkle")
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    @MainActor func checkForUpdates() {
        logger.info("Sparkle: manual update check requested")
        updaterController.checkForUpdates(nil)
    }

    private func describeItem(_ item: SUAppcastItem) -> String {
        let url = item.fileURL?.absoluteString ?? "nil"
        return "display=\(item.displayVersionString) version=\(item.versionString) url=\(url)"
    }

    private func logError(_ error: Error, context: String) {
        let nsError = error as NSError
        let reason = nsError.localizedFailureReason ?? "nil"
        logger.error("\(context, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) desc=\(nsError.localizedDescription, privacy: .public) reason=\(reason, privacy: .public)")
        if !nsError.userInfo.isEmpty {
            logger.error("Sparkle error userInfo: \(String(describing: nsError.userInfo), privacy: .public)")
        }
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        logger.info("Sparkle: appcast loaded items=\(appcast.items.count)")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        logger.info("Sparkle: valid update found \(self.describeItem(item), privacy: .public)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        logError(error, context: "Sparkle: no update found")
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        logger.error("Sparkle: failed download \(self.describeItem(item), privacy: .public)")
        logError(error, context: "Sparkle: download failure")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        logger.info("Sparkle: will install update \(self.describeItem(item), privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        logError(error, context: "Sparkle: update aborted")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            logError(error, context: "Sparkle: update cycle finished with error")
        } else {
            logger.info("Sparkle: update cycle finished (check=\(updateCheck.rawValue))")
        }
    }
}

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
