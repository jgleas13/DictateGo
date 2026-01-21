import AppKit
import SwiftUI

struct StatusView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DictateGo")
                .font(.headline)
            Text(appState.status.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Hold \(appState.hotkey.displayString) to record")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
