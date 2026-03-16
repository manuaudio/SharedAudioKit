//
//  MIDISender.swift
//  CoreMIDIKit
//
//  MIDI output: program changes (with optional bank select),
//  control changes, and SysEx messages.
//

import Foundation
import CoreMIDI

/// Sends MIDI messages (PC, CC, SysEx) to a destination endpoint.
///
/// All sends are dispatched to a serial queue to prevent contention.
/// Bank select messages are sent before program changes when specified.
public final class MIDISender {
    private let outputPort: MIDIPortRef
    private let queue = DispatchQueue(label: "com.manuaudio.midi.sender", qos: .userInitiated)

    public init(outputPort: MIDIPortRef) {
        self.outputPort = outputPort
    }

    /// Send a Program Change with optional bank select.
    public func sendProgramChange(program: Int, channel: Int, bankMSB: Int? = nil, bankLSB: Int? = nil, destination: MIDIEndpointRef, log: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if let msb = bankMSB {
                self.sendCC(number: 0, value: msb, channel: channel, destination: destination, log: log)
            }
            if let lsb = bankLSB {
                self.sendCC(number: 32, value: lsb, channel: channel, destination: destination, log: log)
            }
            let status = UInt8(0xC0 | ((channel - 1) & 0x0F))
            let bytes: [UInt8] = [status, UInt8(program & 0x7F)]
            self.send(bytes: bytes, destination: destination)
        }
    }

    /// Send a Control Change message.
    public func sendControlChange(number: Int, value: Int, channel: Int, destination: MIDIEndpointRef, log: @escaping (String) -> Void) {
        queue.async { [weak self] in
            self?.sendCC(number: number, value: value, channel: channel, destination: destination, log: log)
        }
    }

    /// Send a SysEx message from a hex string.
    public func sendSysEx(hexString: String, destination: MIDIEndpointRef, log: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let cleaned = hexString.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "")

            guard !cleaned.isEmpty, cleaned.count % 2 == 0 else {
                DispatchQueue.main.async { log("ERROR: Invalid SysEx hex length") }
                return
            }

            guard cleaned.count / 2 <= 1024 else {
                DispatchQueue.main.async { log("ERROR: SysEx too large (max 1024 bytes)") }
                return
            }

            var bytes: [UInt8] = []
            bytes.reserveCapacity(cleaned.count / 2)
            var index = cleaned.startIndex
            while index < cleaned.endIndex {
                let nextIndex = cleaned.index(index, offsetBy: 2)
                let byteString = cleaned[index..<nextIndex]
                if let byte = UInt8(byteString, radix: 16) {
                    bytes.append(byte)
                } else {
                    DispatchQueue.main.async { log("ERROR: Invalid SysEx hex character") }
                    return
                }
                index = nextIndex
            }

            if bytes.first != 0xF0 { bytes.insert(0xF0, at: 0) }
            if bytes.last != 0xF7 { bytes.append(0xF7) }

            self.sendSysExBytes(bytes, destination: destination, log: log)
            DispatchQueue.main.async { log("Sent SysEx \(bytes.count) bytes") }
        }
    }

    private func sendCC(number: Int, value: Int, channel: Int, destination: MIDIEndpointRef, log: @escaping (String) -> Void) {
        let status = UInt8(0xB0 | ((channel - 1) & 0x0F))
        let bytes: [UInt8] = [status, UInt8(number & 0x7F), UInt8(value & 0x7F)]
        send(bytes: bytes, destination: destination)
        log("Sent CC ch\(channel) \(number)=\(value)")
    }

    @discardableResult
    private func send(bytes: [UInt8], destination: MIDIEndpointRef) -> OSStatus {
        var packetList = MIDIPacketList(numPackets: 1, packet: MIDIPacket())
        let result = bytes.withUnsafeBufferPointer { buffer -> OSStatus in
            var packet = MIDIPacketListInit(&packetList)
            packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
            return MIDISend(outputPort, destination, &packetList)
        }
        return result
    }

    private func sendSysExBytes(_ bytes: [UInt8], destination: MIDIEndpointRef, log: @escaping (String) -> Void) {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
        buffer.initialize(from: bytes, count: bytes.count)
        let request = UnsafeMutablePointer<MIDISysexSendRequest>.allocate(capacity: 1)
        request.initialize(to: MIDISysexSendRequest(
            destination: destination,
            data: buffer,
            bytesToSend: UInt32(bytes.count),
            complete: false,
            reserved: (0, 0, 0),
            completionProc: { requestPtr in
                requestPtr.pointee.data.deallocate()
                requestPtr.deinitialize(count: 1)
                requestPtr.deallocate()
            },
            completionRefCon: nil
        ))
        _ = MIDISendSysex(request)
    }
}
