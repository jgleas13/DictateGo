import AppKit
import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCapturingHotkey = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            switch appState.onboardingStep {
            case .welcome:
                OnboardingWelcomeView(onContinue: {
                    appState.onboardingStep = .setup
                })
            case .setup:
                OnboardingSetupView(
                    steps: SetupStepsBuilder.steps(for: appState),
                    completed: appState.onboardingCompletedSteps,
                    total: appState.onboardingTotalSteps,
                    onAction: handleSetupAction
                )
            case .complete:
                OnboardingCompleteView(
                    onFinish: {
                        WindowCoordinator.shared.closeOnboarding()
                    },
                    onOpenSettings: {
                        WindowCoordinator.shared.closeOnboarding()
                        WindowCoordinator.shared.showSettings(appState: appState)
                    }
                )
            }
        }
        .frame(minWidth: 720, minHeight: 640)
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
            if appState.isOnboardingComplete && !appState.onboardingPreviewMode {
                appState.onboardingStep = .complete
            }
        }
        .onChange(of: appState.onboardingStep) { _, step in
            if step == .setup && appState.onboardingPreviewMode && appState.isOnboardingComplete {
                appState.onboardingStep = .complete
            }
        }
        .onChange(of: appState.isOnboardingComplete) { _, isComplete in
            if isComplete && !appState.onboardingPreviewMode {
                appState.onboardingStep = .complete
            }
        }
        .onChange(of: appState.onboardingCompletedSteps) { _, _ in
            if appState.onboardingStep == .setup && appState.isOnboardingComplete {
                appState.onboardingStep = .complete
            }
        }
        .onDisappear {
            appState.onboardingPreviewMode = false
            appState.stopPermissionPolling()
        }
    }

    private func handleSetupAction(_ step: SetupStepModel) {
        switch step.id {
        case .hotkey:
            isCapturingHotkey = true
        case .microphone:
            appState.startMicTest()
        case .accessibility:
            appState.noteAccessibilityRequestAttempt()
            let granted = appState.requestAccessibilityAccess()
            if !granted {
                openSystemSettings("Privacy_Accessibility")
            }
        }
    }

    private func openSystemSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "shield.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    )

                Text("Before we begin")
                    .font(.system(size: 24, weight: .semibold))
                Text("To transcribe your speech and paste it anywhere, we'll need a couple of permissions from your Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            SettingsCard {
                VStack(spacing: 16) {
                    OnboardingPermissionRow(
                        icon: "mic",
                        title: "Microphone",
                        subtitle: "To hear your voice and transcribe your words"
                    )

                    OnboardingPermissionRow(
                        icon: "keyboard",
                        title: "Accessibility",
                        subtitle: "To type the transcribed text into any app"
                    )
                }
                .padding(20)
            }
            .frame(maxWidth: 420)

            Text("Your privacy matters. All transcription happens on-device - nothing is sent to the cloud.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

private struct OnboardingPermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingSetupView: View {
    let steps: [SetupStepModel]
    let completed: Int
    let total: Int
    let onAction: (SetupStepModel) -> Void

    var body: some View {
        VStack(spacing: 18) {
            SetupCard(
                completed: completed,
                total: total,
                steps: steps,
                action: onAction
            )
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 32)
    }
}

private struct OnboardingCompleteView: View {
    @EnvironmentObject private var appState: AppState
    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    @FocusState private var demoFieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.16))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    )

                Text("Let's test your microphone")
                    .font(.system(size: 24, weight: .semibold))

                HStack(spacing: 6) {
                    Text("Press and hold the")
                    KeyCapLabel(text: appState.hotkey.displayString)
                    Text("key to dictate your first sentence.")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $appState.onboardingDemoText)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .focused($demoFieldFocused)
                    .onChange(of: demoFieldFocused) { focused in
                        appState.onboardingDemoFieldFocused = focused
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)

                if appState.onboardingDemoText.isEmpty {
                    Text("Your words will appear here...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
            )
            .frame(maxWidth: 520)

            Button(primaryButtonTitle) {
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPrimaryButtonDisabled)

            Button("Skip") {
                onFinish()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == 2 ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            appState.startOnboardingDemo()
            demoFieldFocused = true
            appState.onboardingDemoFieldFocused = true
        }
        .onDisappear {
            appState.stopOnboardingDemo()
        }
    }
}

private extension OnboardingCompleteView {
    var isPrimaryButtonDisabled: Bool {
        appState.onboardingDemoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var primaryButtonTitle: String {
        isPrimaryButtonDisabled ? "Dictate something to continue" : "Close and Complete Setup"
    }
}

private struct KeyCapLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
    }
}
