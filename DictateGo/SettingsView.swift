import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCapturingHotkey = false
    @State private var showAdvanced = false
    private let trailingColumnWidth: CGFloat = 260
    private let controlHeight: CGFloat = 28
    private let micPickerWidth: CGFloat = 320

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    if !attentionSteps.isEmpty {
                        attentionSection
                    }

                    Text("Settings")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)

                    activationSection
                    inputSection
                    advancedSection

                }
                .frame(width: 720, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            guard !isPreview else { return }
            appState.refreshInputDevices()
            appState.refreshPermissionStatus()
            appState.startPermissionPolling()
        }
        .onChange(of: appState.showDockIcon) { _, _ in
            guard !isPreview else { return }
            WindowCoordinator.shared.updateDockVisibility(appState: appState)
        }
        .onDisappear {
            guard !isPreview else { return }
            appState.stopPermissionPolling()
        }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ActionRequiredCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.red)
                            .font(.system(size: 12, weight: .semibold))
                        Text("Action required")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.red)
                    }

                    Text("One or more required items were deactivated. Please resolve to keep dictation working.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(spacing: 0) {
                    ForEach(attentionSteps) { step in
                        ActionRequiredStepRow(step: step) {
                            handleSetupAction(step)
                        }

                        if step.id != (attentionSteps.last?.id ?? step.id) {
                            Divider()
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var activationSection: some View {
        SettingsSection(title: "ACTIVATION") {
            SettingsCard {
                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hotkey")
                            .font(.system(size: 13))
                        Text("The shortcut used to start dictation.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    trailingColumn {
                        HStack(spacing: 8) {
                            KeyBadge(text: appState.hotkey.displayString)
                            Button("Change") {
                                isCapturingHotkey = true
                            }
                            .controlSize(.regular)
                            .buttonStyle(.bordered)
                            // Keep content-sized so trailing edge aligns with the column boundary.
                            .frame(height: controlHeight)
                            .fixedSize()
                        }
                    }
                }

                Divider()

                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activation mode")
                            .font(.system(size: 13))
                        Text("Press and hold the hotkey while speaking or press it to start and to stop.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    trailingColumn {
                        Picker("", selection: $appState.activationMode) {
                            ForEach(ActivationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.regular)
                        .frame(height: controlHeight)
                    }
                }
            }
        }
    }

    private var inputSection: some View {
        SettingsSection(title: "Input") {
            SettingsCard {
                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone")
                            .font(.system(size: 13))
                        Text("The device used for capturing audio.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    trailingColumn {
                        Picker("", selection: Binding(
                            get: { appState.selectedInputDeviceUID },
                            set: { appState.selectInputDevice($0) }
                        )) {
                            Text(inputDeviceLabel).tag("")
                            ForEach(appState.availableInputDevices) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.regular)
                        .frame(height: controlHeight)
                        .frame(width: micPickerWidth, alignment: .trailing)
                    }
                }

                Divider()

                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Input Level")
                            .font(.system(size: 13))
                        Text("Speak to test your microphone volume.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    trailingColumn {
                        HStack(spacing: 10) {
                            MicLevelIndicator(level: appState.micLevel)
                            Text(micLevelStatus)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Button(appState.isMicTesting ? "Stop Test" : "Test Mic") {
                                appState.startMicTest()
                            }
                            .controlSize(.regular)
                            .buttonStyle(.bordered)
                            // Keep content-sized so trailing edge aligns with the column boundary.
                            .frame(height: controlHeight)
                            .fixedSize()
                        }
                    }
                }
            }
        }
    }

    private var advancedSection: some View {
        VStack(spacing: 20) {
            advancedToggleRow

            if showAdvanced {
                playbackSection
                feedbackSection
                dockSection
                troubleshootingSection
            }
        }
    }

    private var advancedToggleRow: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.6))
                .frame(height: 1)
            Button(showAdvanced ? "Hide Advanced" : "Show Advanced") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showAdvanced.toggle()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(width: 150, height: controlHeight)
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.6))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var playbackSection: some View {
        SettingsSection(title: "Playback") {
            SettingsCard {
                SettingsToggleRow(isOn: $appState.pauseSystemAudio) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause media playback")
                            .font(.system(size: 13))
                        Text("Pauses music and video while dictation is active.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var feedbackSection: some View {
        SettingsSection(title: "Feedback") {
            SettingsCard {
                SettingsToggleRow(isOn: $appState.playSounds) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play start sound")
                            .font(.system(size: 13))
                        Text("Plays a tone to confirm dictation has started.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var dockSection: some View {
        SettingsSection(title: "Window") {
            SettingsCard {
                SettingsToggleRow(isOn: $appState.openAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at Login")
                            .font(.system(size: 13))
                        Text("Automatically launches the app when you log in.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                SettingsToggleRow(isOn: $appState.showRecordingBar) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show recording bar")
                            .font(.system(size: 13))
                        Text("Displays an on-screen visualizer while recording.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                SettingsToggleRow(isOn: $appState.showDockIcon) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in Dock")
                            .font(.system(size: 13))
                        Text("Keeps the app icon visible in the Dock.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var troubleshootingSection: some View {
        SettingsSection(title: "Troubleshooting") {
            SettingsCard {
                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Event Logging")
                            .font(.system(size: 13))
                        Text("Record app activity to help troubleshoot issues.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    Button(appState.diagnosticsEnabled ? "Stop Recording" : "Start Recording") {
                        if appState.diagnosticsEnabled {
                            appState.stopDiagnosticsSession()
                        } else {
                            appState.startDiagnosticsSession()
                        }
                    }
                    .controlSize(.regular)
                    .buttonStyle(.borderedProminent)
                    .tint(appState.diagnosticsEnabled ? .red : .gray)
                    .frame(minHeight: controlHeight)
                }

                if appState.diagnosticsEnabled {
                    Divider()

                    if appState.eventLog.isEmpty {
                        SettingsRow {
                            Text("No events recorded yet.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } trailing: {
                            EmptyView()
                        }
                    } else {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Text("Time")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                Text("Event")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                            Divider()

                            LazyVStack(spacing: 0) {
                                ForEach(appState.eventLog.indices.reversed(), id: \.self) { index in
                                    let entry = appState.eventLog[index]
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(DictateGoFormatters.logTime.string(from: entry.timestamp))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 90, alignment: .leading)
                                        Text(entry.message)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)

                                    if index != appState.eventLog.startIndex {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.5))
                        )
                    }
                }
            }
        }
    }

    private var inputDeviceLabel: String {
        let name = appState.defaultInputDeviceName
        if name.isEmpty || name == "Unknown" {
            return "System default"
        }
        return "System default (\(name))"
    }

    private var micLevelStatus: String {
        appState.micLevel > 0.15 ? "Active" : "Idle"
    }

    private var setupSteps: [SetupStepModel] {
        SetupStepsBuilder.steps(for: appState)
    }

    private var attentionSteps: [SetupStepModel] {
        setupSteps.filter { !$0.isComplete }
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

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private func trailingColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
        }
        .frame(width: trailingColumnWidth, alignment: .trailing)
        .debugBorder(.red.opacity(0.6), enabled: false)
    }

}

private struct KeyBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7))
            )
    }
}

private struct MicLevelIndicator: View {
    let level: Float

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(level > 0.15 ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
            MiniLevelBar(level: level)
                .frame(width: 80, height: 6)
        }
    }
}

private struct MiniLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: max(3, CGFloat(level) * geo.size.width))
            }
        }
    }
}

private struct ActionRequiredCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.06))
        )
    }
}

private struct ActionRequiredStepRow: View {
    let step: SetupStepModel
    let action: () -> Void
    private let controlHeight: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1.2)
                Image(systemName: step.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 13, weight: .medium))
                Text(step.detail.map { "\(step.description) \($0)" } ?? step.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(step.actionTitle) {
                action()
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .frame(height: controlHeight)
            .fixedSize()
            .disabled(step.actionDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppState.preview())
            .frame(width: 1024, height: 900)
    }
}
#endif
