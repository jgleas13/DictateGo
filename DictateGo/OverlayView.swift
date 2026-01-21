import AppKit
import SwiftUI

private let overlayAccent = Color(red: 0.88, green: 0.94, blue: 1.0)

struct OverlayView: View {
    @EnvironmentObject private var state: OverlayState

    var body: some View {
        Group {
            switch state.status {
            case .hidden:
                EmptyView()
            case .recording, .speaking:
                ListeningPill(
                    level: state.audioLevel,
                    isSpeaking: state.status == .speaking,
                    isActive: true
                )
            case .transcribing:
                TranscribingPill()
            case .error:
                ErrorPill(
                    title: state.errorTitle,
                    subtitle: state.errorSubtitle,
                    onDismiss: { state.dismiss() }
                )
            case .toast:
                ToastPill(
                    message: state.toastMessage,
                    duration: state.toastDuration,
                    onComplete: { state.dismiss() }
                )
            case .airPodsWarning:
                AirPodsWarningPill(
                    onChangeMic: {
                        openDictateGoSettings()
                        state.dismiss()
                    },
                    onIgnore: { state.dismiss() }
                )
            }
        }
    }
}

private struct ListeningPill: View {
    let level: Float
    let isSpeaking: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            DotRow(level: level, isSpeaking: isSpeaking, isActive: isActive)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.9))
        )
        .overlay(
            Capsule()
                .stroke(overlayAccent.opacity(isActive ? 0.6 : 0.0), lineWidth: 1.5)
        )
        .frame(width: 180, height: 44)
        .animation(.easeInOut(duration: 0.12), value: level)
    }
}

private struct TranscribingPill: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(overlayAccent.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .scaleEffect(animate ? 1.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.9))
        )
        .frame(width: 180, height: 44)
        .onAppear { animate = true }
    }
}

private struct ToastPill: View {
    let message: String
    let duration: TimeInterval
    let onComplete: () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.blue.opacity(0.9))
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                    Capsule()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: max(2, proxy.size.width * progress))
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .onAppear {
            progress = 0
            withAnimation(.linear(duration: duration)) {
                progress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                onComplete()
            }
        }
    }
}

private struct DotRow: View {
    let level: Float
    let isSpeaking: Bool
    let isActive: Bool
    private let dotCount = 9

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { index in
                let weight = dotWeight(for: index)
                Circle()
                    .fill(overlayAccent.opacity(isActive ? 0.75 : 0.35))
                    .frame(width: 4, height: 4)
                    .scaleEffect(dotScale(weight: weight))
                    .offset(y: dotOffset(weight: weight))
            }
        }
    }

    private func dotWeight(for index: Int) -> CGFloat {
        let center = CGFloat(dotCount - 1) / 2
        let distance = abs(CGFloat(index) - center)
        return max(0.2, 1 - (distance / center))
    }

    private func dotScale(weight: CGFloat) -> CGFloat {
        let base: CGFloat = 0.8
        guard isSpeaking else { return base }
        let amplitude = CGFloat(min(1, max(0.05, level)))
        return base + amplitude * 0.9 * weight
    }

    private func dotOffset(weight: CGFloat) -> CGFloat {
        guard isSpeaking else { return 0 }
        let amplitude = CGFloat(min(1, max(0.05, level)))
        return -amplitude * 6 * weight
    }
}

private struct ErrorPill: View {
    let title: String
    let subtitle: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.red)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 10) {
                Button("Select microphone") {
                    openSoundInputSettings()
                }
                .buttonStyle(OverlayActionButtonStyle())

                Button("Troubleshoot") {
                    openMicrophonePrivacy()
                }
                .buttonStyle(OverlayActionButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.95))
        )
        .frame(width: 440, height: 128)
    }
}

private struct AirPodsWarningPill: View {
    let onChangeMic: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "headphones")
                    .foregroundStyle(overlayAccent)
                Text("AirPods aren’t the best for dictation")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }

            Text("They can add delay and hurt accuracy. Your built-in mic will give you better results.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 10) {
                Button("Change mic", action: onChangeMic)
                    .buttonStyle(OverlayActionButtonStyle())
                Button("Ignore", action: onIgnore)
                    .buttonStyle(OverlayActionButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.95))
        )
        .frame(width: 440, height: 128)
    }
}

private func openSoundInputSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound?input") else { return }
    NSWorkspace.shared.open(url)
}

private func openMicrophonePrivacy() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
    NSWorkspace.shared.open(url)
}

private func openDictateGoSettings() {
    Task { @MainActor in
        WindowCoordinator.shared.showSettings(appState: AppState.shared)
    }
}

private struct OverlayActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0.15))
            )
    }
}
