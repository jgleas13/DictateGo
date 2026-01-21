import AppKit
import SwiftUI

struct GettingStartedView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCapturingHotkey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Getting Started")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Finish setup to unlock settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Progress \(appState.onboardingCompletedSteps) of \(appState.onboardingTotalSteps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(appState.onboardingCompletedSteps), total: Double(appState.onboardingTotalSteps))
                }

                OnboardingStepCard(
                    title: "Set hotkey",
                    detail: "Choose the shortcut used to start dictation.",
                    isComplete: appState.hotkeyConfigured,
                    actionTitle: "Set Hotkey"
                ) {
                    isCapturingHotkey = true
                } accessory: {
                    HStack {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        KeyCapBadge(text: appState.hotkey.displayString)
                    }
                }

                OnboardingStepCard(
                    title: "Allow microphone",
                    detail: "Required for transcription.",
                    isComplete: appState.microphoneAuthorized,
                    actionTitle: appState.microphoneAuthorized ? "Test Mic" : "Request Access"
                ) {
                    appState.startMicTest()
                } accessory: {
                    if appState.isMicTesting {
                        LevelBar(level: appState.micLevel)
                    } else {
                        Text(appState.microphoneAuthorized ? "Access granted." : "Access not granted. Enable it in System Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                OnboardingStepCard(
                    title: "Allow accessibility",
                    detail: "Needed to paste into active apps.",
                    isComplete: appState.accessibilityAuthorized,
                    actionTitle: "Open Settings"
                ) {
                    appState.noteAccessibilityRequestAttempt()
                    openSystemSettings("Privacy_Accessibility")
                } accessory: {
                    if appState.accessibilityAuthorized {
                        Text("Access granted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Access not granted. Enable it in System Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let emphasis = appState.accessibilityEmphasisDetail {
                                Text(emphasis)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.top, 4)
                            }
                        }
                    }
                }

                Text("Settings will appear once all steps are complete.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 640, minHeight: 560)
            .sheet(isPresented: $isCapturingHotkey) {
                HotkeyCaptureSheet(
                    currentHotkey: appState.hotkey,
                    allowsModifierOnly: true,
                    onSave: { hotkey in
                        appState.setHotkey(hotkey)
                        isCapturingHotkey = false
                    },
                    onCancel: {
                        isCapturingHotkey = false
                    }
                )
            }
            .onAppear {
            appState.refreshPermissionStatus()
            appState.startPermissionPolling()
        }
        .onDisappear {
            appState.stopPermissionPolling()
        }
    }

    private func openSystemSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct OnboardingStepCard<Accessory: View>: View {
    let title: String
    let detail: String
    let isComplete: Bool
    let actionTitle: String
    let isActionDisabled: Bool
    let action: () -> Void
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        detail: String,
        isComplete: Bool,
        actionTitle: String,
        isActionDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.detail = detail
        self.isComplete = isComplete
        self.actionTitle = actionTitle
        self.isActionDisabled = isActionDisabled
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? .green : .secondary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .disabled(isActionDisabled)
            }

            accessory
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor))
        )
    }
}
