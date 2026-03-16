//
//  MTCGenerator.swift
//  CoreMIDIKit
//
//  MTC quarter-frame generator for timecode output via MIDI.
//  Generates the 8 quarter-frame messages per frame required by MTC.
//

import Foundation
import CoreMIDI

/// Generates MTC (MIDI Time Code) quarter-frame messages for timecode output.
///
/// Feed it the current timecode position via `updateTimecode()`, set a destination
/// endpoint, and call `start()`. The generator sends 8 quarter-frame messages per
/// frame at the configured rate.
public final class MTCGenerator {
    private let outputPort: MIDIPortRef
    private let queue = DispatchQueue(label: "com.manuaudio.mtc.generator", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var running = false
    private var pieceIndex: UInt8 = 0
    private var framesPerSecond: Int
    private var mtcRateBits: UInt8
    private var destination: MIDIEndpointRef?
    private var currentHours: Int = 0
    private var currentMinutes: Int = 0
    private var currentSeconds: Int = 0
    private var currentFrames: Int = 0

    public init(outputPort: MIDIPortRef, framesPerSecond: Int = 30, mtcRateBits: UInt8 = 3) {
        self.outputPort = outputPort
        self.framesPerSecond = framesPerSecond
        self.mtcRateBits = mtcRateBits
    }

    /// Set or clear the MIDI destination for MTC output.
    public func updateDestination(_ destination: MIDIEndpointRef?) {
        queue.async { [weak self] in
            self?.destination = destination
        }
    }

    /// Update the current timecode position being transmitted.
    public func updateTimecode(hours: Int, minutes: Int, seconds: Int, frames: Int) {
        queue.async { [weak self] in
            self?.currentHours = hours
            self?.currentMinutes = minutes
            self?.currentSeconds = seconds
            self?.currentFrames = frames
        }
    }

    /// Update the frame rate for MTC generation.
    public func updateFrameRate(framesPerSecond: Int, mtcRateBits: UInt8) {
        queue.async { [weak self] in
            guard let self else { return }
            self.framesPerSecond = framesPerSecond
            self.mtcRateBits = mtcRateBits
            if self.running {
                self.restartTimer()
            }
        }
    }

    /// Start generating MTC quarter-frame messages.
    public func start() {
        queue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.pieceIndex = 0
            self.startTimer()
        }
    }

    /// Stop generating MTC.
    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.timer?.cancel()
            self.timer = nil
            self.pieceIndex = 0
        }
    }

    private func startTimer() {
        let fps = max(1, framesPerSecond)
        let interval = 1.0 / Double(fps * 8)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        startTimer()
    }

    private func tick() {
        guard running else { return }
        guard let destination else { return }

        let dataByte = quarterFrameData(for: pieceIndex)
        sendQuarterFrame(dataByte, destination: destination)
        pieceIndex = (pieceIndex + 1) & 0x07
    }

    private func quarterFrameData(for piece: UInt8) -> UInt8 {
        let value: UInt8
        switch piece {
        case 0:
            value = UInt8(currentFrames & 0x0F)
        case 1:
            value = UInt8((currentFrames >> 4) & 0x03)
        case 2:
            value = UInt8(currentSeconds & 0x0F)
        case 3:
            value = UInt8((currentSeconds >> 4) & 0x03)
        case 4:
            value = UInt8(currentMinutes & 0x0F)
        case 5:
            value = UInt8((currentMinutes >> 4) & 0x03)
        case 6:
            value = UInt8(currentHours & 0x0F)
        default:
            let hourMsb = UInt8((currentHours >> 4) & 0x01)
            value = UInt8((mtcRateBits << 1) | hourMsb)
        }
        return (piece << 4) | (value & 0x0F)
    }

    private func sendQuarterFrame(_ dataByte: UInt8, destination: MIDIEndpointRef) {
        let bytes: [UInt8] = [0xF1, dataByte]
        var packetList = MIDIPacketList(numPackets: 1, packet: MIDIPacket())
        _ = bytes.withUnsafeBufferPointer { buffer -> OSStatus in
            var packet = MIDIPacketListInit(&packetList)
            packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
            return MIDISend(outputPort, destination, &packetList)
        }
    }
}
