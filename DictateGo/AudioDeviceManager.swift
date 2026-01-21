import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let deviceID: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool

    var id: String { uid }
}

enum AudioDeviceManager {
    static func availableInputDevices() -> [AudioInputDevice] {
        let deviceIDs = allDeviceIDs()
        let defaultID = defaultInputDeviceID()
        let devices = deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            guard let name = deviceName(deviceID: deviceID),
                  let uid = deviceUID(deviceID: deviceID) else {
                return nil
            }
            guard hasInputChannels(deviceID: deviceID) else { return nil }
            guard isDeviceAlive(deviceID: deviceID) else { return nil }
            guard !isAggregateOrVirtualDevice(deviceID: deviceID) else { return nil }
            guard !isLikelyVirtualName(name) else { return nil }
            return AudioInputDevice(
                deviceID: deviceID,
                uid: uid,
                name: name,
                isDefault: deviceID == defaultID
            )
        }
        return devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultInputDeviceName() -> String {
        guard let deviceID = defaultInputDeviceID(),
              let name = deviceName(deviceID: deviceID) else {
            return "Unknown"
        }
        return name
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
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

    static func deviceID(for uid: String) -> AudioDeviceID? {
        availableInputDevices().first(where: { $0.uid == uid })?.deviceID
    }

    static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        deviceUID(deviceID: deviceID)
    }

    static func deviceName(for deviceID: AudioDeviceID) -> String? {
        deviceName(deviceID: deviceID)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard dataStatus == noErr else { return [] }
        return deviceIDs
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let bufferPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferPointer.deallocate() }

        let bufferList = bufferPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let listStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList)
        guard listStatus == noErr else { return false }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    static func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let bufferPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferPointer.deallocate() }

        let bufferList = bufferPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let listStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList)
        guard listStatus == noErr else { return false }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    private static func isDeviceAlive(deviceID: AudioDeviceID) -> Bool {
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive)
        guard status == noErr else { return true }
        return alive != 0
    }

    private static func isAggregateOrVirtualDevice(deviceID: AudioDeviceID) -> Bool {
        guard let transport = deviceTransportType(deviceID: deviceID) else { return false }
        return transport == kAudioDeviceTransportTypeAggregate
            || transport == kAudioDeviceTransportTypeVirtual
    }

    private static func isLikelyVirtualName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix("cadefaultdeviceaggregate") {
            return true
        }
        return false
    }

    private static func deviceTransportType(deviceID: AudioDeviceID) -> UInt32? {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        guard status == noErr else { return nil }
        return transport
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        guard status == noErr else { return nil }
        return name as String
    }

    private static func deviceUID(deviceID: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        guard status == noErr else { return nil }
        return uid as String
    }
}
