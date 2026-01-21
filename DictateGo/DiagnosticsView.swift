import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("About")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)

                    SettingsSection(title: "Details") {
                        SettingsCard {
                            SettingsRow {
                                Text("App version")
                                    .font(.system(size: 13))
                            } trailing: {
                                Text(appVersionString)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            SettingsRow {
                                Text("Hotkey")
                                    .font(.system(size: 13))
                            } trailing: {
                                Text(appState.hotkey.displayString)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            SettingsRow {
                                Text("Accessibility")
                                    .font(.system(size: 13))
                            } trailing: {
                                Text(appState.accessibilityAuthorized ? "Granted" : "Not granted")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            SettingsRow {
                                Text("Microphone")
                                    .font(.system(size: 13))
                            } trailing: {
                                Text(appState.microphoneAuthorized ? "Granted" : "Not granted")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            SettingsRow {
                                Text("Model status")
                                    .font(.system(size: 13))
                            } trailing: {
                                Text(appState.modelStatus.label)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            SettingsRow {
                                Text("Recording status")
                                    .font(.system(size: 13))
                            } trailing: {
                                Text(appState.status.rawValue)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            SettingsRow {
                                Text("Input device")
                                    .font(.system(size: 13))
                            } trailing: {
                                Text(appState.inputDeviceName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                        }
                    }

                }
                .frame(width: 720, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
