//
//  MTCDecoder.swift
//  MTCKit
//
//  Pure byte-level MTC (MIDI Timecode) decoder.
//  Handles quarter-frame and full-frame SysEx messages.
//  No CoreMIDI dependency — the caller feeds raw MIDI bytes.
//

import Foundation
import TimecodeKit

/// Pure MTC decoder — processes raw MIDI bytes, no CoreMIDI dependency.
///
/// Usage:
/// ```swift
/// let decoder = MTCDecoder()
/// decoder.onTimecode = { tc, rate in print("MTC: \(tc.displayString)") }
/// // Feed bytes from your MIDI input handler:
/// for byte in midiData { decoder.processByte(byte) }
/// ```
public final class MTCDecoder {

    // MARK: - Callbacks

    /// Called when a complete quarter-frame decode produces a new timecode.
    /// The timecode is corrected for MTC's 2-frame transmission delay.
    public var onTimecode: ((Timecode, FrameRate) -> Void)?

    /// Called when a full-frame SysEx message is received (locate/jump).
    /// This is an exact position with no transmission delay.
    public var onFullFrame: ((Timecode, FrameRate) -> Void)?

    // MARK: - Public State

    /// The most recently decoded timecode.
    public private(set) var timecode: Timecode = .zero

    /// The detected frame rate from the most recent decode.
    public private(set) var frameRate: FrameRate = .fps30

    // MARK: - Internal State

    private var quarterFrameBuffer: [UInt8] = Array(repeating: 0, count: 8)
    private var quarterFrameReceivedMask: UInt8 = 0
    private var lastStatusByte: UInt8 = 0
    private var expectingQuarterFrameData = false
    private var suppressNextQFDecode = false

    // SysEx accumulation (capped at 256 bytes to prevent OOM on malformed streams)
    private var sysExBuffer: [UInt8] = []
    private var inSysEx = false
    private static let maxSysExLength = 256

    /// Timestamp of the last successfully decoded timecode.
    public private(set) var lastDecodeTime: CFAbsoluteTime = 0

    /// Whether the decoder has active MTC input (received valid timecode within the last 1 second).
    public var isActive: Bool {
        CFAbsoluteTimeGetCurrent() - lastDecodeTime < 1.0
    }

    // MARK: - Rate Lookup

    private static let rates: [(fps: Double, drop: Bool, rate: FrameRate)] = [
        (24.0, false, .fps24),
        (25.0, false, .fps25),
        (29.97, true, .fps2997df),
        (30.0, false, .fps30),
    ]

    // MARK: - Init

    public init() {}

    /// Reset all decoder state.
    public func reset() {
        quarterFrameBuffer = Array(repeating: 0, count: 8)
        quarterFrameReceivedMask = 0
        lastStatusByte = 0
        expectingQuarterFrameData = false
        suppressNextQFDecode = false
        sysExBuffer.removeAll()
        inSysEx = false
        timecode = .zero
        frameRate = .fps30
        lastDecodeTime = 0
    }

    // MARK: - Byte Processing

    /// Feed a single MIDI byte to the decoder.
    public func processByte(_ byte: UInt8) {
        // --- SysEx accumulation ---
        if byte == 0xF0 {
            inSysEx = true
            sysExBuffer.removeAll()
            return
        }
        if inSysEx {
            if byte == 0xF7 {
                inSysEx = false
                handleSysEx(sysExBuffer)
                sysExBuffer.removeAll()
                return
            } else if byte & 0x80 != 0 {
                inSysEx = false
                sysExBuffer.removeAll()
                // Fall through to handle this status byte
            } else {
                sysExBuffer.append(byte)
                if sysExBuffer.count > Self.maxSysExLength {
                    inSysEx = false
                    sysExBuffer.removeAll()
                }
                return
            }
        }

        // --- Quarter-frame handling ---
        if byte & 0x80 != 0 {
            lastStatusByte = byte
            expectingQuarterFrameData = (byte == 0xF1)
            return
        }

        guard expectingQuarterFrameData || lastStatusByte == 0xF1 else { return }
        expectingQuarterFrameData = false

        let messageType = (byte >> 4) & 0x07
        let nibble = byte & 0x0F
        guard messageType < 8 else { return }

        if messageType == 0 {
            quarterFrameReceivedMask = 0
        }

        quarterFrameBuffer[Int(messageType)] = nibble
        quarterFrameReceivedMask |= (1 << messageType)

        if quarterFrameReceivedMask == 0xFF {
            decodeTimecode()
            quarterFrameReceivedMask = 0
        }
    }

    /// Feed multiple MIDI bytes at once.
    public func processBytes(_ bytes: [UInt8]) {
        for byte in bytes { processByte(byte) }
    }

    // MARK: - Full-Frame MTC (SysEx)

    /// Handle MTC Full-Frame: F0 7F <dev> 01 01 hr mn sc fr F7
    private func handleSysEx(_ data: [UInt8]) {
        guard data.count >= 8,
              data[0] == 0x7F,
              data[2] == 0x01,
              data[3] == 0x01
        else { return }

        let hr = data[4]
        let rateCode = Int((hr >> 5) & 0x03)
        let hours = Int(hr & 0x1F)
        let minutes = Int(data[5] & 0x7F)
        let seconds = Int(data[6] & 0x7F)
        let frames = Int(data[7] & 0x7F)

        let rateInfo = Self.rates[rateCode]
        let rate = rateInfo.rate

        let tc = Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames)
        timecode = tc
        frameRate = rate

        // Suppress next QF decode — it carries stale data from before the locate
        quarterFrameReceivedMask = 0
        suppressNextQFDecode = true

        lastDecodeTime = CFAbsoluteTimeGetCurrent()
        onFullFrame?(tc, rate)
    }

    // MARK: - Quarter-Frame Decode

    private func decodeTimecode() {
        let rawFrames = Int(quarterFrameBuffer[0] | (quarterFrameBuffer[1] << 4))
        let seconds = Int(quarterFrameBuffer[2] | (quarterFrameBuffer[3] << 4))
        let minutes = Int(quarterFrameBuffer[4] | (quarterFrameBuffer[5] << 4))
        let hours = Int(quarterFrameBuffer[6] | ((quarterFrameBuffer[7] & 0x01) << 4)) & 0x1F

        let rateCode = Int((quarterFrameBuffer[7] >> 1) & 0x03)
        let rateInfo = Self.rates[rateCode]
        let rate = rateInfo.rate
        let fps = rate.fps

        if suppressNextQFDecode {
            suppressNextQFDecode = false
            return
        }

        let raw = Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: rawFrames)

        // MTC compensation: QF7 arrives 2 frames after the encoded value.
        let corrected = raw.adding(frames: -2, fps: fps, dropFrame: rate.isDropFrame)

        timecode = corrected
        frameRate = rate
        lastDecodeTime = CFAbsoluteTimeGetCurrent()
        onTimecode?(corrected, rate)
    }
}
