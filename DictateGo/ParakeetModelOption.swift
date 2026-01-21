import Foundation
import FluidAudio

enum ParakeetModelOption: String, CaseIterable, Identifiable, Codable {
    case tdtV3 = "parakeet-tdt-0.6b-v3-coreml"
    case tdtV2 = "parakeet-tdt-0.6b-v2-coreml"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tdtV3:
            return "Parakeet TDT v3 (Multilingual)"
        case .tdtV2:
            return "Parakeet TDT v2 (English)"
        }
    }

    var version: AsrModelVersion {
        switch self {
        case .tdtV3:
            return .v3
        case .tdtV2:
            return .v2
        }
    }
}
