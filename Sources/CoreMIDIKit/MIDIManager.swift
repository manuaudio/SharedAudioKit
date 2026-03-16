//
//  MIDIManager.swift
//  CoreMIDIKit
//
//  Single CoreMIDI client with input and output port management.
//  One MIDIManager per app — replaces duplicated boilerplate.
//

import Foundation
import CoreMIDI

/// Errors that can occur during MIDI setup.
public enum MIDIManagerError: LocalizedError {
    case clientCreationFailed(OSStatus)
    case inputPortCreationFailed(OSStatus)
    case outputPortCreationFailed(OSStatus)
    case sendFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .clientCreationFailed(let s): return "Failed to create MIDI client (error \(s))"
        case .inputPortCreationFailed(let s): return "Failed to create input port (error \(s))"
        case .outputPortCreationFailed(let s): return "Failed to create output port (error \(s))"
        case .sendFailed(let s): return "MIDI send failed (error \(s))"
        }
    }
}

/// Manages a single CoreMIDI client with input and output ports.
///
/// Usage:
/// ```swift
/// guard let midi = MIDIManager(clientName: "MyApp") else { /* MIDI unavailable */ }
/// try midi.createInputPort(name: "Input") { message in ... }
/// try midi.createOutputPort(name: "Output")
/// midi.connectAllSources()
/// try midi.send([0xC0, 42], to: destinationEndpoint)
/// ```
public final class MIDIManager {

    public private(set) var client: MIDIClientRef = 0
    public private(set) var inputPort: MIDIPortRef = 0
    public private(set) var outputPort: MIDIPortRef = 0

    /// Current MIDI sources (refreshed on setup change).
    public private(set) var sources: [MIDIEndpointInfo] = []
    /// Current MIDI destinations (refreshed on setup change).
    public private(set) var destinations: [MIDIEndpointInfo] = []

    /// Called when the MIDI setup changes (device plug/unplug).
    public var onSetupChanged: (() -> Void)?

    private var inputCallback: ((MIDIMessage) -> Void)?
    private var callbackQueue: DispatchQueue = .main

    /// Create a MIDI manager. Returns nil if the CoreMIDI client cannot be created.
    public init?(clientName: String) {
        let status = MIDIClientCreateWithBlock(clientName as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async {
                    self?.refreshEndpoints()
                    self?.onSetupChanged?()
                }
            }
        }
        guard status == noErr else { return nil }
        refreshEndpoints()
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Port Creation

    /// Create an input port that parses MIDI events and delivers MIDIMessage values.
    /// - Parameters:
    ///   - name: Port name visible in CoreMIDI.
    ///   - callbackQueue: Queue for callback dispatch (default: main). Use a dedicated
    ///     queue for high-throughput scenarios (e.g. 1000+ CC/sec modulation).
    ///   - callback: Called for each parsed MIDI message.
    public func createInputPort(name: String, callbackQueue: DispatchQueue = .main, callback: @escaping (MIDIMessage) -> Void) throws {
        self.inputCallback = callback
        self.callbackQueue = callbackQueue
        let status = MIDIInputPortCreateWithProtocol(
            client, name as CFString, ._1_0, &inputPort
        ) { [weak self] eventList, _ in
            self?.handleEventList(eventList)
        }
        guard status == noErr else {
            throw MIDIManagerError.inputPortCreationFailed(status)
        }
    }

    /// Create an output port for sending MIDI data.
    public func createOutputPort(name: String) throws {
        let status = MIDIOutputPortCreate(client, name as CFString, &outputPort)
        guard status == noErr else {
            throw MIDIManagerError.outputPortCreationFailed(status)
        }
    }

    // MARK: - Connections

    /// Connect the input port to all available MIDI sources.
    public func connectAllSources() {
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            MIDIPortConnectSource(inputPort, MIDIGetSource(i), nil)
        }
    }

    /// Connect the input port to a specific source.
    public func connect(to source: MIDIEndpointRef) {
        MIDIPortConnectSource(inputPort, source, nil)
    }

    /// Disconnect the input port from a specific source.
    public func disconnect(from source: MIDIEndpointRef) {
        MIDIPortDisconnectSource(inputPort, source)
    }

    // MARK: - Sending

    /// Send raw MIDI bytes to a destination.
    public func send(_ bytes: [UInt8], to destination: MIDIEndpointRef) throws {
        guard outputPort != 0 else { return }
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, baseAddress)
        }
        let status = MIDISend(outputPort, destination, &packetList)
        guard status == noErr else {
            throw MIDIManagerError.sendFailed(status)
        }
    }

    /// Send multiple MIDI messages in a single packet list (more efficient for automation curves).
    public func sendBatch(_ messages: [[UInt8]], to destination: MIDIEndpointRef) throws {
        guard outputPort != 0 else { return }
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        for msg in messages {
            msg.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, msg.count, base)
            }
        }
        let status = MIDISend(outputPort, destination, &packetList)
        guard status == noErr else {
            throw MIDIManagerError.sendFailed(status)
        }
    }

    // MARK: - Send Helpers

    /// Send a Control Change message.
    public func sendCC(channel: UInt8, controller: UInt8, value: UInt8, to dest: MIDIEndpointRef) throws {
        try send([0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F], to: dest)
    }

    /// Send a Program Change message.
    public func sendProgramChange(channel: UInt8, program: UInt8, to dest: MIDIEndpointRef) throws {
        try send([0xC0 | (channel & 0x0F), program & 0x7F], to: dest)
    }

    /// Send a Note On message.
    public func sendNoteOn(channel: UInt8, note: UInt8, velocity: UInt8, to dest: MIDIEndpointRef) throws {
        try send([0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F], to: dest)
    }

    /// Send a Note Off message.
    public func sendNoteOff(channel: UInt8, note: UInt8, velocity: UInt8, to dest: MIDIEndpointRef) throws {
        try send([0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F], to: dest)
    }

    // MARK: - Connect by Unique ID

    /// Connect input port to a MIDI source identified by unique ID.
    /// Returns true if the source was found and connected.
    @discardableResult
    public func connect(toSourceWithUniqueID uid: Int32) -> Bool {
        guard let endpoint = findSourceByUniqueID(uid) else { return false }
        MIDIPortConnectSource(inputPort, endpoint, nil)
        return true
    }

    /// Disconnect input port from a MIDI source identified by unique ID.
    /// Returns true if the source was found and disconnected.
    @discardableResult
    public func disconnect(fromSourceWithUniqueID uid: Int32) -> Bool {
        guard let endpoint = findSourceByUniqueID(uid) else { return false }
        MIDIPortDisconnectSource(inputPort, endpoint)
        return true
    }

    // MARK: - Endpoint Enumeration

    /// Refresh the lists of available sources and destinations.
    public func refreshEndpoints() {
        sources = enumerateMIDISources()
        destinations = enumerateMIDIDestinations()
    }

    // MARK: - Event Parsing

    private func handleEventList(_ eventListPtr: UnsafePointer<MIDIEventList>) {
        let numPackets = Int(eventListPtr.pointee.numPackets)
        guard numPackets > 0 else { return }

        // We must iterate through the original event list memory, NOT a stack copy.
        // MIDIEventPacketNext computes the next packet address by offsetting from
        // the current pointer, so it must point into the original contiguous buffer.
        //
        // UnsafeMutablePointer dance: get a pointer to the `packet` field within
        // the original event list allocation.
        let firstPacketPtr = UnsafeRawPointer(eventListPtr)
            .advanced(by: 8)  // skip protocol (UInt32) + numPackets (UInt32)
            .assumingMemoryBound(to: MIDIEventPacket.self)

        var current: UnsafePointer<MIDIEventPacket> = firstPacketPtr
        for _ in 0..<numPackets {
            parseAndDispatchPacket(current.pointee)
            current = MIDIEventPacketNext(current)
        }
    }

    private func parseAndDispatchPacket(_ packet: MIDIEventPacket) {
        guard packet.wordCount >= 1 else { return }
        let word = packet.words.0
        let messageType = (word >> 28) & 0x0F

        if messageType == 0x02 { // MIDI 1.0 channel voice
            let status = UInt8((word >> 16) & 0xFF)
            let data1 = UInt8((word >> 8) & 0xFF)
            let data2 = UInt8(word & 0xFF)
            let message = MIDIMessage.parse(status: status, data1: data1, data2: data2)

            callbackQueue.async { [weak self] in
                self?.inputCallback?(message)
            }
        } else if messageType == 0x01 { // MIDI 1.0 system common
            let status = UInt8((word >> 16) & 0xFF)
            let data1 = UInt8((word >> 8) & 0xFF)
            let data2 = UInt8(word & 0xFF)
            let message: MIDIMessage
            if status == 0xF1 {
                message = .quarterFrame(data: data1)
            } else {
                message = .other(status: status, data1: data1, data2: data2)
            }

            callbackQueue.async { [weak self] in
                self?.inputCallback?(message)
            }
        } else if messageType == 0x03 { // MIDI 1.0 SysEx (64-bit)
            let sysExStatus = UInt8((word >> 20) & 0x0F)
            let numBytes = Int(UInt8((word >> 16) & 0x0F))
            var bytes: [UInt8] = []

            if numBytes >= 1 { bytes.append(UInt8((word >> 8) & 0xFF)) }
            if numBytes >= 2 { bytes.append(UInt8(word & 0xFF)) }

            if packet.wordCount >= 2 && numBytes > 2 {
                let word2 = packet.words.1
                if numBytes >= 3 { bytes.append(UInt8((word2 >> 24) & 0xFF)) }
                if numBytes >= 4 { bytes.append(UInt8((word2 >> 16) & 0xFF)) }
                if numBytes >= 5 { bytes.append(UInt8((word2 >> 8) & 0xFF)) }
                if numBytes >= 6 { bytes.append(UInt8(word2 & 0xFF)) }
            }

            // sysExStatus: 0=complete, 1=start, 2=continue, 3=end
            let message = MIDIMessage.sysEx(data: bytes)

            callbackQueue.async { [weak self] in
                self?.inputCallback?(message)
            }
        }
    }
}
