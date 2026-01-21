import Foundation
import FluidAudio

enum TranscriptionError: LocalizedError {
    case notConfigured
    case modelNotDownloaded
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Transcription is not configured yet."
        case .modelNotDownloaded:
            return "The transcription model is not downloaded yet."
        case .modelNotLoaded:
            return "The transcription model is not loaded yet."
        }
    }
}

actor TranscriptionManager {
    private let engine = ParakeetEngine()

    func isModelAvailable(_ model: ParakeetModelOption) -> Bool {
        let directory = AsrModels.defaultCacheDirectory(for: model.version)
        if AsrModels.modelsExist(at: directory, version: model.version) {
            return true
        }
        guard let bundledDirectory = bundledModelDirectory(for: model) else {
            return false
        }
        return AsrModels.modelsExist(at: bundledDirectory, version: model.version)
    }

    func downloadModel(_ model: ParakeetModelOption) async throws {
        if try stageBundledModelIfNeeded(model) {
            return
        }
        _ = try await AsrModels.download(version: model.version)
    }

    func loadModelIfNeeded(_ model: ParakeetModelOption) async throws {
        let staged = try stageBundledModelIfNeeded(model)
        guard staged || isModelAvailable(model) else {
            throw TranscriptionError.modelNotDownloaded
        }
        try await engine.load(version: model.version)
    }

    func transcribe(audioURL: URL, model: ParakeetModelOption) async throws -> String {
        try await loadModelIfNeeded(model)
        let prepared = try ParakeetAudioPreparer.prepare(url: audioURL)
        defer {
            if let cleanup = prepared.cleanupURL {
                try? FileManager.default.removeItem(at: cleanup)
            }
        }
        return try await engine.transcribe(url: prepared.url)
    }

    func clearModelCache(_ model: ParakeetModelOption) async {
        await engine.reset()
        let directory = AsrModels.defaultCacheDirectory(for: model.version)
        try? FileManager.default.removeItem(at: directory)
    }

    private func bundledModelDirectory(for model: ParakeetModelOption) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }
        let candidates = [
            resourceURL.appendingPathComponent("Models", isDirectory: true),
            resourceURL.appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true),
        ]
        let fileManager = FileManager.default
        for base in candidates {
            let directory = base.appendingPathComponent(model.rawValue, isDirectory: true)
            if fileManager.fileExists(atPath: directory.path) {
                return directory
            }
        }
        return nil
    }

    private func stageBundledModelIfNeeded(_ model: ParakeetModelOption) throws -> Bool {
        let cacheDirectory = AsrModels.defaultCacheDirectory(for: model.version)
        if AsrModels.modelsExist(at: cacheDirectory, version: model.version) {
            return true
        }
        guard let bundledDirectory = bundledModelDirectory(for: model),
              AsrModels.modelsExist(at: bundledDirectory, version: model.version)
        else {
            return false
        }
        let fileManager = FileManager.default
        let parentDirectory = cacheDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
        try fileManager.copyItem(at: bundledDirectory, to: cacheDirectory)
        return true
    }
}
