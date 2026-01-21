import SwiftUI

enum SetupStepID: String, CaseIterable {
    case hotkey
    case microphone
    case accessibility
}

struct SetupStepModel: Identifiable {
    let id: SetupStepID
    let title: String
    let description: String
    let detail: String?
    let emphasisDetail: String?
    let icon: String
    let isComplete: Bool
    let actionTitle: String
    let actionDisabled: Bool
    let forceShowAction: Bool
}

@MainActor
enum SetupStepsBuilder {
    static func steps(for appState: AppState) -> [SetupStepModel] {
        let hotkeyDescription = "Use \(appState.hotkey.displayString) to start dictation, or assign a new hotkey."
        let micDetail = appState.microphoneAuthorized ? nil : "Access not granted. Enable it in System Settings."
        let accessibilityDetail = appState.accessibilityAuthorized
            ? nil
            : "Access not granted. Enable it in System Settings."
        let accessibilityEmphasisDetail = appState.accessibilityEmphasisDetail

        return [
            SetupStepModel(
                id: .hotkey,
                title: "Set hotkey",
                description: hotkeyDescription,
                detail: nil,
                emphasisDetail: nil,
                icon: "command",
                isComplete: appState.hotkeyConfigured,
                actionTitle: "Change",
                actionDisabled: false,
                forceShowAction: true
            ),
            SetupStepModel(
                id: .microphone,
                title: "Allow microphone",
                description: "Required for transcription.",
                detail: micDetail,
                emphasisDetail: nil,
                icon: "mic",
                isComplete: appState.microphoneAuthorized,
                actionTitle: appState.microphoneAuthorized ? "Test Mic" : "Request Access",
                actionDisabled: false,
                forceShowAction: false
            ),
            SetupStepModel(
                id: .accessibility,
                title: "Allow accessibility",
                description: "Needed to paste into active apps.",
                detail: accessibilityDetail,
                emphasisDetail: accessibilityEmphasisDetail,
                icon: "hand.raised",
                isComplete: appState.accessibilityAuthorized,
                actionTitle: "Request Access",
                actionDisabled: false,
                forceShowAction: false
            )
        ]
    }
}

struct SetupCard: View {
    let completed: Int
    let total: Int
    let steps: [SetupStepModel]
    let action: (SetupStepModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Setup")
                    .font(.system(size: 20, weight: .semibold))
                Text("Finish setup to unlock dictation.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Progress")
                    Spacer()
                    Text("\(completed) of \(total)")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                ProgressView(value: Double(completed), total: Double(total))
                    .controlSize(.small)
            }
            .padding(20)

            Divider()

            VStack(spacing: 0) {
                ForEach(steps) { step in
                    SetupStepRow(step: step) {
                        action(step)
                    }

                    if step.id != (steps.last?.id ?? step.id) {
                        Divider()
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7))
        )
    }
}

struct SetupStepRow: View {
    let step: SetupStepModel
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if step.isComplete {
                ZStack {
                    Circle()
                        .fill(Color.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1.5)
                    Image(systemName: step.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 13, weight: .medium))
                Text(step.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let detail = step.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let emphasisDetail = step.emphasisDetail {
                    Text(emphasisDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            if !step.isComplete || step.forceShowAction {
                if step.isComplete {
                    Button(step.actionTitle) {
                        action()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .disabled(step.actionDisabled)
                } else {
                    Button(step.actionTitle) {
                        action()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(step.actionDisabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SetupDotRow: View {
    let total: Int
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
