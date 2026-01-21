import SwiftUI

struct KeyCapBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel(Text("Hotkey \(text)"))
    }
}

struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.08))
                Capsule()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: max(6, CGFloat(level) * geo.size.width))
            }
        }
        .frame(height: 10)
        .animation(.easeInOut(duration: 0.1), value: level)
    }
}

struct StatusPill: View {
    let status: ModelStatus

    var body: some View {
        let meta = statusMeta
        Text(meta.label)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(meta.color.opacity(0.15)))
            .foregroundStyle(meta.color)
    }

    private var statusMeta: (label: String, color: Color) {
        switch status {
        case .ready:
            return ("Ready", .green)
        case .missing:
            return ("Not downloaded", .secondary)
        case .checking:
            return ("Checking", .secondary)
        case .downloading:
            return ("Downloading", .orange)
        case .failed:
            return ("Error", .red)
        }
    }
}

struct ComingSoonBadge: View {
    var body: some View {
        Text("Coming soon")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .foregroundStyle(.secondary)
    }
}

enum DictateGoFormatters {
    static let shortTime: Foundation.DateFormatter = {
        let formatter = Foundation.DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let logTime: Foundation.DateFormatter = {
        let formatter = Foundation.DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
