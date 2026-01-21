import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = WindowCoordinator()

    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func updateDockVisibility(appState: AppState) {
        applyDockVisibility(appState: appState)
    }

    func showOnboarding(appState: AppState) {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingFlowView()
            .environmentObject(appState)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "DictateGo"
        window.setContentSize(NSSize(width: 720, height: 640))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    func showSettings(appState: AppState) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsContainerView()
            .environmentObject(appState)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 1024, height: 900))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == onboardingWindow {
            onboardingWindow = nil
        } else if window == settingsWindow {
            settingsWindow = nil
        }
    }

    private func applyDockVisibility(appState: AppState) {
        setActivationPolicy(showDockIcon: appState.showDockIcon)
    }

    private func setActivationPolicy(showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
