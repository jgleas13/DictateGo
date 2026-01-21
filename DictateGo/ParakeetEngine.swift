import Foundation
import FluidAudio

actor ParakeetEngine {
    private var manager: AsrManager?
    private var currentVersion: AsrModelVersion?

    func load(version: AsrModelVersion) async throws {
        if currentVersion == version, manager?.isAvailable == true {
            return
        }

        let models = try await AsrModels.loadFromCache(version: version)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)

        self.manager = manager
        self.currentVersion = version
    }

    func transcribe(url: URL) async throws -> String {
        guard let manager else {
            throw TranscriptionError.modelNotLoaded
        }

        let result = try await manager.transcribe(url, source: .microphone)
        return result.text
    }

    func reset() {
        manager = nil
        currentVersion = nil
    }
}
