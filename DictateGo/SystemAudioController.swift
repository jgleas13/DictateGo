import AppKit
import CoreAudio
import MediaPlayer

enum SystemAudioController {
    private static let playPauseKey: Int32 = 16

    static func shouldPauseSystemAudio() -> Bool {
        hasActiveNowPlayingSession()
    }

    static func isOutputAudioActive() -> Bool {
        guard let deviceID = outputDeviceID() else { return false }
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let runningStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &isRunning
        )
        guard runningStatus == noErr else { return false }
        return isRunning != 0
    }

    static func togglePlayPause(shouldPreventMusicLaunch: Bool, onMusicLaunched: (() -> Void)? = nil) {
        let musicBundleID = "com.apple.Music"
        let wasMusicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleID).isEmpty
        sendMediaKey(playPauseKey)

        guard shouldPreventMusicLaunch, !wasMusicRunning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleID)
            guard !apps.isEmpty else { return }
            apps.forEach { $0.terminate() }
            onMusicLaunched?()
        }
    }

    private static func outputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func hasActiveNowPlayingSession() -> Bool {
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        return !(info?.isEmpty ?? true)
    }

    private static func sendMediaKey(_ key: Int32) {
        let keyDown = (Int(key) << 16) | 0xA00
        let keyUp = (Int(key) << 16) | 0xB00
        postSystemDefinedEvent(data1: keyDown)
        postSystemDefinedEvent(data1: keyUp)
    }

    private static func postSystemDefinedEvent(data1: Int) {
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
