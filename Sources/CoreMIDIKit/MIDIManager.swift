//
//  MIDIManager.swift
//  CoreMIDIKit
//
//  Single CoreMIDI client with input and output port management.
//  One MIDIManager per app — replaces duplicated boilerplate.
//

import Foundation
import CoreMIDI

/// Manages a single CoreMIDI client with input and output ports.
///
/// Usage:
/// ```swift
/// let midi = MIDIManager(clientName: "MyApp")
/// midi.createInputPort(name: "Input") { message in ... }
/// midi.createOutputPort(name: "Output")
/// midi.connectAllSources()
/// midi.send([0xC0, 42], to: destinationEndpoint)
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

    public init(clientName: String) {
        let status = MIDIClientCreateWithBlock(clientName as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async {
                    self?.refreshEndpoints()
                    self?.onSetupChanged?()
                }
            }
        }
        if status != noErr {
            print("[CoreMIDIKit] Failed to create client: \(status)")
        }
        refreshEndpoints()
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Port Creation

    /// Create an input port that parses MIDI events and delivers MIDIMessage values.
    public func createInputPort(name: String, callback: @escaping (MIDIMessage) -> Void) {
        self.inputCallback = callback
        let status = MIDIInputPortCreateWithProtocol(
            client, name as CFString, ._1_0, &inputPort
        ) { [weak self] eventList, _ in
            self?.handleEventList(eventList)
        }
        if status != noErr {
            print("[CoreMIDIKit] Failed to create input port: \(status)")
        }
    }

    /// Create an output port for sending MIDI data.
    public func createOutputPort(name: String) {
        let status = MIDIOutputPortCreate(client, name as CFString, &outputPort)
        if status != noErr {
            print("[CoreMIDIKit] Failed to create output port: \(status)")
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
    public func send(_ bytes: [UInt8], to destination: MIDIEndpointRef) {
        guard outputPort != 0 else { return }
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, baseAddress)
        }
        MIDISend(outputPort, destination, &packetList)
    }

    // MARK: - Endpoint Enumeration

    /// Refresh the lists of available sources and destinations.
    public func refreshEndpoints() {
        sources = enumerateMIDISources()
        destinations = enumerateMIDIDestinations()
    }

    // MARK: - Event Parsing

    private func handleEventList(_ eventListPtr: UnsafePointer<MIDIEventList>) {
        let eventList = eventListPtr.pointee
        var packet = eventList.packet

        for _ in 0..<eventList.numPackets {
            if packet.wordCount >= 1 {
                let word = packet.words.0
                let messageType = (word >> 28) & 0x0F

                if messageType == 0x02 { // MIDI 1.0 channel voice
                    let status = UInt8((word >> 16) & 0xFF)
                    let data1 = UInt8((word >> 8) & 0xFF)
                    let data2 = UInt8(word & 0xFF)
                    let message = MIDIMessage.parse(status: status, data1: data1, data2: data2)

                    DispatchQueue.main.async { [weak self] in
                        self?.inputCallback?(message)
                    }
                }
            }

            var current = packet
            withUnsafePointer(to: &current) { ptr in
                packet = MIDIEventPacketNext(ptr).pointee
            }
        }
    }
}
