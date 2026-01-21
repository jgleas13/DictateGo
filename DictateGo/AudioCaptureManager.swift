import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMedia
import Foundation

final class AudioCaptureManager: NSObject {
    private static let outputAudioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: true,
        AVLinearPCMIsBigEndianKey: false,
    ]
    private let sessionQueue = DispatchQueue(label: "AudioCaptureManager.Session")
    private let sampleBufferQueue = DispatchQueue(label: "AudioCaptureManager.SampleBuffer")
    private var session: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var meterHandler: ((Float) -> Void)?

    func startRecording(deviceID: AudioDeviceID?) throws {
        stopCaptureSession()
        let filename = "recording-\(UUID().uuidString).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        currentURL = url
        audioFile = nil

        let (session, output) = try configureSession(deviceID: deviceID)
        self.session = session
        self.audioOutput = output

        sessionQueue.sync {
            session.startRunning()
        }
        guard session.isRunning else {
            stopCaptureSession()
            throw AudioCaptureError.failedToStart(nil)
        }
    }

    func stopRecording() -> URL? {
        stopMetering()
        let url = currentURL
        stopCaptureSession()
        return url
    }

    func startMetering(_ handler: @escaping (Float) -> Void) {
        meterHandler = handler
    }

    func stopMetering() {
        meterHandler = nil
    }

    private static func level(from buffer: AVAudioPCMBuffer) -> Float {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sumSquares: Float = 0
        if let floatData = buffer.floatChannelData {
            for channel in 0..<channelCount {
                let data = floatData[channel]
                for index in 0..<frameLength {
                    let sample = data[index]
                    sumSquares += sample * sample
                }
            }
        } else if let int16Data = buffer.int16ChannelData {
            let scale = 1.0 / Float(Int16.max)
            for channel in 0..<channelCount {
                let data = int16Data[channel]
                for index in 0..<frameLength {
                    let sample = Float(data[index]) * scale
                    sumSquares += sample * sample
                }
            }
        }

        let meanSquare = sumSquares / Float(frameLength * channelCount)
        let rms = sqrt(meanSquare)
        let power = 20 * log10(max(rms, 0.000_001))
        return normalizedPowerLevel(power)
    }

    private static func normalizedPowerLevel(_ power: Float) -> Float {
        let minDb: Float = -60
        if power < minDb { return 0 }
        if power > 0 { return 1 }
        return (power - minDb) / -minDb
    }

    private func configureSession(deviceID: AudioDeviceID?) throws -> (AVCaptureSession, AVCaptureAudioDataOutput) {
        let session = AVCaptureSession()
        let device = try captureDevice(for: deviceID)
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = Self.outputAudioSettings
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw AudioCaptureError.failedToConfigureSession("Unable to add audio input.")
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw AudioCaptureError.failedToConfigureSession("Unable to add audio output.")
        }
        session.addOutput(output)
        session.commitConfiguration()

        return (session, output)
    }

    private func captureDevice(for deviceID: AudioDeviceID?) throws -> AVCaptureDevice {
        let devices = AVCaptureDevice.devices(for: .audio)
        guard !devices.isEmpty else {
            throw AudioCaptureError.failedToSelectCaptureDevice("No audio capture devices available.")
        }
        guard let deviceID else {
            if let device = AVCaptureDevice.default(for: .audio) {
                return device
            }
            throw AudioCaptureError.failedToSelectCaptureDevice("System default capture device not found.")
        }

        if let uid = AudioDeviceManager.deviceUID(for: deviceID),
           let device = devices.first(where: { $0.uniqueID == uid }) {
            return device
        }
        if let name = AudioDeviceManager.deviceName(for: deviceID),
           let device = devices.first(where: { $0.localizedName == name }) {
            return device
        }
        if let device = AVCaptureDevice.default(for: .audio) {
            return device
        }
        throw AudioCaptureError.failedToSelectCaptureDevice("Selected mic could not be mapped to a capture device.")
    }

    private func stopCaptureSession() {
        sessionQueue.sync {
            session?.stopRunning()
        }
        session = nil
        audioOutput = nil
        audioFile = nil
        currentURL = nil
    }
}

enum AudioCaptureError: LocalizedError {
    case failedToStart(Error?)
    case failedToSelectDevice(OSStatus)
    case failedToSelectCaptureDevice(String)
    case failedToConfigureSession(String)

    var errorDescription: String? {
        switch self {
        case .failedToStart(let error):
            if let error {
                return "Microphone failed to start recording: \(error.localizedDescription)"
            }
            return "Microphone failed to start recording."
        case .failedToSelectDevice(let status):
            return "Failed to select microphone (OSStatus \(status))."
        case .failedToSelectCaptureDevice(let reason):
            return "Failed to select microphone: \(reason)"
        case .failedToConfigureSession(let reason):
            return "Microphone failed to start recording: \(reason)"
        }
    }
}

extension AudioCaptureManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pcmBuffer = Self.pcmBuffer(from: sampleBuffer),
              let url = currentURL else {
            return
        }
        if audioFile == nil {
            do {
                audioFile = try AVAudioFile(
                    forWriting: url,
                    settings: pcmBuffer.format.settings,
                    commonFormat: pcmBuffer.format.commonFormat,
                    interleaved: pcmBuffer.format.isInterleaved
                )
            } catch {
                return
            }
        }
        do {
            try audioFile?.write(from: pcmBuffer)
        } catch {
            return
        }
        if let meterHandler = meterHandler {
            let level = Self.level(from: pcmBuffer)
            DispatchQueue.main.async {
                meterHandler(level)
            }
        }
    }
}

extension AudioCaptureManager {
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        var bufferListSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr else { return nil }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let srcBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let dstBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        guard srcBuffers.count == dstBuffers.count else { return nil }

        for index in 0..<srcBuffers.count {
            let src = srcBuffers[index]
            let dst = dstBuffers[index]
            guard let srcData = src.mData, let dstData = dst.mData else { continue }
            let byteCount = min(Int(src.mDataByteSize), Int(dst.mDataByteSize))
            if byteCount > 0 {
                memcpy(dstData, srcData, byteCount)
            }
        }

        return pcmBuffer
    }
}
