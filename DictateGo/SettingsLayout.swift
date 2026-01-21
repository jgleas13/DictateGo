import AppKit
import SwiftUI

private enum SettingsLayoutDebug {
    static let enabled = false
}

extension View {
    @ViewBuilder
    func debugBorder(_ color: Color, enabled: Bool) -> some View {
        if enabled {
            self.overlay(Rectangle().stroke(color, lineWidth: 1))
        } else {
            self
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7))
        )
    }
}

struct SettingsRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .debugBorder(.blue.opacity(0.6), enabled: SettingsLayoutDebug.enabled)
    }
}

struct SettingsToggleRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let label: Label

    var body: some View {
        HStack(spacing: 16) {
            label
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .debugBorder(.purple.opacity(0.6), enabled: SettingsLayoutDebug.enabled)
    }
}
