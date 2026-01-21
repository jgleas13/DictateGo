import AVFoundation
import Foundation

struct ParakeetPreparedAudio {
    let url: URL
    let cleanupURL: URL?
}

enum ParakeetAudioPreparer {
    private static let minimumDuration: TimeInterval = 1.5

    static func prepare(url: URL) throws -> ParakeetPreparedAudio {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        let duration = Double(frameCount) / format.sampleRate

        guard duration < minimumDuration else {
            return ParakeetPreparedAudio(url: url, cleanupURL: nil)
        }

        let targetFrames = AVAudioFrameCount(ceil(minimumDuration * format.sampleRate))
        let readBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        guard let readBuffer else {
            return ParakeetPreparedAudio(url: url, cleanupURL: nil)
        }
        try file.read(into: readBuffer)

        let paddedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: targetFrames)
        guard let paddedBuffer else {
            return ParakeetPreparedAudio(url: url, cleanupURL: nil)
        }
        paddedBuffer.frameLength = targetFrames

        if let dest = paddedBuffer.floatChannelData, let src = readBuffer.floatChannelData {
            let bytes = Int(targetFrames) * MemoryLayout<Float>.size
            memset(dest[0], 0, bytes)
            let copyBytes = Int(readBuffer.frameLength) * MemoryLayout<Float>.size
            memcpy(dest[0], src[0], copyBytes)
        } else if let dest = paddedBuffer.int16ChannelData, let src = readBuffer.int16ChannelData {
            let bytes = Int(targetFrames) * MemoryLayout<Int16>.size
            memset(dest[0], 0, bytes)
            let copyBytes = Int(readBuffer.frameLength) * MemoryLayout<Int16>.size
            memcpy(dest[0], src[0], copyBytes)
        } else {
            return ParakeetPreparedAudio(url: url, cleanupURL: nil)
        }

        let paddedURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-padded.wav")

        let outputFile = try AVAudioFile(forWriting: paddedURL, settings: file.fileFormat.settings)
        try outputFile.write(from: paddedBuffer)

        return ParakeetPreparedAudio(url: paddedURL, cleanupURL: paddedURL)
    }
}
