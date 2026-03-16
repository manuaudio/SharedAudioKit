//
//  MIDIMessage.swift
//  CoreMIDIKit
//
//  Parsed MIDI message types.
//

import Foundation

/// A parsed MIDI channel voice or system message.
public enum MIDIMessage: Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case programChange(channel: UInt8, program: UInt8)
    case quarterFrame(data: UInt8)
    case sysEx(data: [UInt8])
    case other(status: UInt8, data1: UInt8, data2: UInt8)

    /// The raw MIDI bytes for this message. Useful for feeding to MTCDecoder.
    public var bytes: [UInt8] {
        switch self {
        case .noteOn(let ch, let n, let v): return [0x90 | ch, n, v]
        case .noteOff(let ch, let n, let v): return [0x80 | ch, n, v]
        case .controlChange(let ch, let cc, let v): return [0xB0 | ch, cc, v]
        case .programChange(let ch, let p): return [0xC0 | ch, p]
        case .quarterFrame(let d): return [0xF1, d]
        case .sysEx(let data): return [0xF0] + data + [0xF7]
        case .other(let s, let d1, let d2): return [s, d1, d2]
        }
    }

    /// Parse a 3-byte MIDI channel voice message.
    public static func parse(status: UInt8, data1: UInt8, data2: UInt8) -> MIDIMessage {
        let channel = status & 0x0F
        let statusType = status & 0xF0

        switch statusType {
        case 0x90:
            return data2 > 0
                ? .noteOn(channel: channel, note: data1, velocity: data2)
                : .noteOff(channel: channel, note: data1, velocity: 0)
        case 0x80:
            return .noteOff(channel: channel, note: data1, velocity: data2)
        case 0xB0:
            return .controlChange(channel: channel, controller: data1, value: data2)
        case 0xC0:
            return .programChange(channel: channel, program: data1)
        default:
            return .other(status: status, data1: data1, data2: data2)
        }
    }
}
