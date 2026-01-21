import AppKit
import SwiftUI

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case history = "History"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .settings:
            return "gearshape"
        case .history:
            return "clock.arrow.circlepath"
        case .about:
            return "info.circle"
        }
    }
}

struct SettingsContainerView: View {
    @State private var selection: SettingsDestination = .settings

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection)

            Divider()

            Group {
                switch selection {
                case .settings:
                    SettingsView()
                case .history:
                    HistoryView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, idealWidth: 1024, minHeight: 720, idealHeight: 900)
    }
}

private struct Sidebar: View {
    @Binding var selection: SettingsDestination
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: renderAppIcon(pointSize: 32, scale: displayScale))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .cornerRadius(7)
                Text("DictateGo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 4)

            VStack(spacing: 4) {
                ForEach(SettingsDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: destination.icon)
                                .frame(width: 16, height: 16)
                            Text(destination.rawValue)
                                .font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == destination ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == destination ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(12)
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func renderAppIcon(pointSize: CGFloat, scale: CGFloat) -> NSImage {
        let icon = NSApplication.shared.applicationIconImage
        let pixelSize = CGSize(width: pointSize * scale, height: pointSize * scale)
        let image = NSImage(size: pixelSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon?.draw(in: NSRect(origin: .zero, size: pixelSize))
        image.unlockFocus()
        image.size = CGSize(width: pointSize, height: pointSize)
        return image
    }
}
