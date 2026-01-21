import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isShowingClearHistoryConfirm = false
    @State private var searchText = ""
    private let controlHeight: CGFloat = 30
    private let historyDisplayLimit: Int = 200

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("History")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)

                    SettingsSection(title: "Data Privacy") {
                        SettingsCard {
                            SettingsToggleRow(isOn: $appState.saveHistory) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Save transcription history")
                                        .font(.system(size: 13))
                                    Text("Locally save your text logs for future reference.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    transcriptsSection
                }
                .frame(width: 720, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "Clear all transcripts?",
            isPresented: $isShowingClearHistoryConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                appState.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all saved transcripts from this device.")
        }
    }

    private var transcriptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            transcriptsToolbar

            SettingsCard {
                if filteredHistory.isEmpty {
                    SettingsRow {
                        Text("No transcripts yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } trailing: {
                        EmptyView()
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        let sections = groupedHistory
                        ForEach(sections.indices, id: \.self) { sectionIndex in
                            let section = sections[sectionIndex]
                            HistorySectionHeader(title: section.title)

                            Divider()

                            ForEach(section.items.indices, id: \.self) { index in
                                let item = section.items[index]
                                HistoryRow(
                                    item: item,
                                    onCopy: { copyHistoryItem(item) },
                                    onDelete: { appState.deleteHistoryItem(item) }
                                )

                                if index != section.items.count - 1 {
                                    Divider()
                                }
                            }

                            if sectionIndex != sections.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var transcriptsToolbar: some View {
        HStack(spacing: 12) {
            Text("Transcripts")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Button("Clear All", role: .destructive) {
                    isShowingClearHistoryConfirm = true
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .frame(minWidth: 100, minHeight: controlHeight)
                .disabled(appState.history.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filteredHistory: [HistoryItem] {
        let items = appState.history
            .prefix(historyDisplayLimit)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Array(items)
        }
        let query = searchText.lowercased()
        return items.filter { $0.text.lowercased().contains(query) }
    }

    private var groupedHistory: [HistorySection] {
        var order: [Date] = []
        var buckets: [Date: [HistoryItem]] = [:]
        let calendar = Calendar.current

        for item in filteredHistory {
            let day = calendar.startOfDay(for: item.timestamp)
            if buckets[day] == nil {
                order.append(day)
                buckets[day] = []
            }
            buckets[day]?.append(item)
        }

        return order.map { date in
            HistorySection(title: sectionTitle(for: date), items: buckets[date] ?? [])
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func copyHistoryItem(_ item: HistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
    }
}

private struct HistorySection {
    let title: String
    let items: [HistoryItem]
}

private struct HistorySectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(HistoryView.timeFormatter.string(from: item.timestamp))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            if isHovering {
                HStack(spacing: 10) {
                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
