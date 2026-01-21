import Foundation

enum ModelStatus: Equatable {
    case checking
    case missing
    case downloading
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .checking:
            return "Checking"
        case .missing:
            return "Not downloaded"
        case .downloading:
            return "Downloading"
        case .ready:
            return "Ready"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}
