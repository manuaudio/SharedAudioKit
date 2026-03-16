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
