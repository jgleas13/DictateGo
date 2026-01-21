import Foundation

enum OverlayStatus: Equatable {
    case hidden
    case recording
    case speaking
    case transcribing
    case error
    case toast
    case airPodsWarning
}

@MainActor
final class OverlayState: ObservableObject {
    @Published var status: OverlayStatus = .hidden
    @Published var audioLevel: Float = 0
    @Published var errorTitle: String = ""
    @Published var errorSubtitle: String = ""
    @Published var toastMessage: String = ""
    @Published var toastDuration: TimeInterval = 3.5
    var onDismiss: (() -> Void)?

    func dismiss() {
        onDismiss?()
    }
}
