//
//  AudioDeviceEnumerator.swift
//  AudioDeviceKit
//
//  CoreAudio HAL device enumeration, channel counting, and hot-plug notification.
//  Pure hardware discovery — no UI state, no persistence.
//  macOS-only: CoreAudio HAL APIs are not available on iOS/visionOS.
//

#if os(macOS)
import Foundation
import CoreAudio

/// Enumerates CoreAudio HAL devices and provides hot-plug notification.
public final class AudioDeviceEnumerator {

    /// Called when the device list changes (plug/unplug).
    public var onDeviceListChanged: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    public init() {
        installDeviceChangeListener()
    }

    deinit {
        removeDeviceChangeListener()
    }

    // MARK: - Enumeration

    /// Enumerate all audio devices. Pass a filter to restrict results.
    public func enumerateDevices(
        filter: ((AudioDeviceInfo) -> Bool)? = nil
    ) -> [AudioDeviceInfo] {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        var result: [AudioDeviceInfo] = []
        for deviceID in deviceIDs {
            let info = AudioDeviceInfo(
                id: deviceID,
                uid: getDeviceUID(deviceID),
                name: getDeviceName(deviceID),
                inputChannels: getChannelCount(deviceID, scope: kAudioDevicePropertyScopeInput),
                outputChannels: getChannelCount(deviceID, scope: kAudioDevicePropertyScopeOutput),
                manufacturer: getDeviceManufacturer(deviceID)
            )
            if let filter = filter {
                if filter(info) { result.append(info) }
            } else {
                result.append(info)
            }
        }
        return result
    }

    // MARK: - Channel Counting

    /// Get channel count for a device in a given scope (input or output).
    public func getChannelCount(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propAddr, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }
        let bufferListPtr = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)

        let status2 = AudioObjectGetPropertyData(deviceID, &propAddr, 0, nil, &dataSize, bufferListPtr)
        guard status2 == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        var total = 0
        for buffer in bufferList { total += Int(buffer.mNumberChannels) }
        return total
    }

    // MARK: - Sample Rate

    /// Get the current nominal sample rate for a device.
    public func getDeviceSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var sampleRate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return status == noErr ? sampleRate : 0
    }

    /// Set the nominal sample rate for a device.
    public func setDeviceSampleRate(_ deviceID: AudioDeviceID, sampleRate: Double) throws {
        var rate = sampleRate
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<Double>.size), &rate
        )
        guard status == noErr else {
            throw AudioDeviceError.sampleRateSetFailed(status)
        }
        // Verify
        let actual = getDeviceSampleRate(deviceID)
        guard abs(actual - sampleRate) < 0.1 else {
            throw AudioDeviceError.sampleRateVerificationFailed
        }
    }

    /// Get available nominal sample rates for a device.
    public func availableSampleRates(_ deviceID: AudioDeviceID) -> [Double] {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propAddr, 0, nil, &dataSize)
        guard status == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        let status2 = AudioObjectGetPropertyData(deviceID, &propAddr, 0, nil, &dataSize, &ranges)
        guard status2 == noErr else { return [] }

        var rates: Set<Double> = []
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                for rate in [44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0] {
                    if rate >= range.mMinimum && rate <= range.mMaximum {
                        rates.insert(rate)
                    }
                }
            }
        }
        return Array(rates).sorted()
    }

    /// Get the system default output device ID.
    public static var systemDefaultOutputDeviceID: AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    /// Format a sample rate for display (e.g., "96 kHz").
    public static func formatSampleRate(_ sampleRate: Double) -> String {
        let khz = sampleRate / 1000.0
        return khz >= 1.0
            ? String(format: "%.0f kHz", khz)
            : String(format: "%.0f Hz", sampleRate)
    }

    // MARK: - Private Helpers

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        getCFStringProperty(deviceID, selector: kAudioDevicePropertyDeviceNameCFString) ?? ""
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String {
        getCFStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? ""
    }

    private func getDeviceManufacturer(_ deviceID: AudioDeviceID) -> String {
        getCFStringProperty(deviceID, selector: kAudioDevicePropertyDeviceManufacturerCFString) ?? ""
    }

    private func getCFStringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propAddr, 0, nil, &size, &result)
        guard status == noErr, let cf = result else { return nil }
        return cf.takeRetainedValue() as String
    }

    // MARK: - Hot-Plug Listener

    private func installDeviceChangeListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.onDeviceListChanged?()
            }
        }
        listenerBlock = block

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
    }

    private func removeDeviceChangeListener() {
        guard let block = listenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
        listenerBlock = nil
    }
}

// MARK: - Errors

public enum AudioDeviceError: LocalizedError {
    case sampleRateSetFailed(OSStatus)
    case sampleRateVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .sampleRateSetFailed(let status):
            return "Failed to set sample rate (error \(status))"
        case .sampleRateVerificationFailed:
            return "Sample rate was not set correctly"
        }
    }
}
#endif
