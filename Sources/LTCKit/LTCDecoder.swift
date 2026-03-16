//
//  LTCDecoder.swift
//  LTCKit
//
//  Decodes Linear Timecode (LTC) from audio samples.
//  SMPTE 12M-1: 80-bit biphase-mark modulated timecode.
//
//  Pipeline: audio samples -> zero-crossings -> bit extraction -> sync word
//  detection -> frame parsing -> Timecode values with sample positions.
//

import Foundation
import TimecodeKit

/// Decodes LTC (SMPTE 12M) timecode from raw audio samples.
///
/// The decoder maintains state between calls, so you can feed it audio
/// in chunks and it will correctly decode across chunk boundaries.
public final class LTCDecoder {

    // MARK: - Configuration

    public let sampleRate: Double

    /// Minimum amplitude to consider a valid transition (reject noise).
    public var noiseFloor: Float = 0.002

    // MARK: - Sync Word

    /// SMPTE 12M sync word: bits 64-79.
    /// In our bitWindow: 0xBFFC.
    private static let syncWord: UInt16 = 0xBFFC

    // MARK: - State

    private var bitWindow: UInt16 = 0
    private var frameBits: [UInt8] = Array(repeating: 0, count: 160)
    private var frameBitsHead: Int = 0
    private var frameBitsCount: Int = 0
    private var frameStartSample: UInt64 = 0
    private var bitCount: Int = 0
    private var prevSample: Float = 0
    private var samplesInHalf: Int = 0
    private var prevHalfDuration: Int = 0
    private var expectingFirstHalf: Bool = true
    private var absoluteSamplePos: UInt64 = 0
    private var estimatedBitDuration: Double = 0
    private var consecutiveGoodFrames: Int = 0

    /// Timestamp of the last successfully decoded frame.
    public private(set) var lastDecodeTime: CFAbsoluteTime = 0

    // MARK: - Init

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.estimatedBitDuration = sampleRate / 2400.0
        reset()
    }

    /// Signal quality (0.0 = no signal, 1.0 = clean lock).
    /// Based on consecutive successful frame decodes. Drops to 0 if no frame decoded within 0.5s.
    public var signalQuality: Float {
        let elapsed = CFAbsoluteTimeGetCurrent() - lastDecodeTime
        if elapsed > 0.5 { return 0.0 }
        return min(1.0, Float(consecutiveGoodFrames) / 10.0)
    }

    /// Whether the decoder has active LTC signal (decoded a frame within the last 0.5 seconds).
    public var isActive: Bool {
        CFAbsoluteTimeGetCurrent() - lastDecodeTime < 0.5
    }

    /// Reset decoder state (call when seeking or switching files).
    public func reset() {
        bitWindow = 0
        frameBitsHead = 0
        frameBitsCount = 0
        frameStartSample = 0
        bitCount = 0
        prevSample = 0
        samplesInHalf = 0
        prevHalfDuration = 0
        expectingFirstHalf = true
        absoluteSamplePos = 0
        consecutiveGoodFrames = 0
        lastDecodeTime = 0
    }

    // MARK: - Decode

    /// Decode LTC frames from a buffer of audio samples.
    public func decode(samples: UnsafeBufferPointer<Float>, sampleOffset: UInt64) -> [LTCFrame] {
        absoluteSamplePos = sampleOffset
        var decoded: [LTCFrame] = []

        for i in 0..<samples.count {
            let sample = samples[i]
            samplesInHalf += 1

            let absPrev = abs(prevSample)
            let absCurr = abs(sample)
            let crossed = (prevSample >= 0 && sample < 0 || prevSample < 0 && sample >= 0)
                && (absPrev > noiseFloor || absCurr > noiseFloor)
            prevSample = sample

            if !crossed {
                absoluteSamplePos += 1
                continue
            }

            let halfDur = samplesInHalf
            let minHalf = Int(estimatedBitDuration * 0.2)
            if halfDur < max(minHalf, 2) {
                absoluteSamplePos += 1
                continue
            }

            let threshold = estimatedBitDuration * 0.75

            if Double(halfDur) < threshold {
                if !expectingFirstHalf {
                    let bitDuration = prevHalfDuration + halfDur
                    pushBit(1, bitDuration: bitDuration, at: absoluteSamplePos)
                    if let frame = checkForFrame() { decoded.append(frame) }
                    updateBitDurationEstimate(Double(bitDuration))
                    expectingFirstHalf = true
                } else {
                    prevHalfDuration = halfDur
                    expectingFirstHalf = false
                }
            } else {
                if !expectingFirstHalf { expectingFirstHalf = true }
                pushBit(0, bitDuration: halfDur, at: absoluteSamplePos)
                if let frame = checkForFrame() { decoded.append(frame) }
                updateBitDurationEstimate(Double(halfDur))
                expectingFirstHalf = true
            }

            samplesInHalf = 0
            absoluteSamplePos += 1
        }

        return decoded
    }

    /// Convenience: decode from a plain [Float] array.
    public func decode(samples: [Float], sampleOffset: UInt64) -> [LTCFrame] {
        samples.withUnsafeBufferPointer { buf in
            decode(samples: buf, sampleOffset: sampleOffset)
        }
    }

    // MARK: - Bit Processing

    private func pushBit(_ bit: UInt8, bitDuration: Int, at samplePos: UInt64) {
        bitWindow = (bitWindow >> 1) | (UInt16(bit) << 15)
        bitCount += 1
        // Circular buffer write — O(1), no array shifting
        let writeIdx = (frameBitsHead + frameBitsCount) % 160
        frameBits[writeIdx] = bit
        if frameBitsCount < 160 {
            frameBitsCount += 1
        } else {
            frameBitsHead = (frameBitsHead + 1) % 160
        }
    }

    private func checkForFrame() -> LTCFrame? {
        guard bitWindow == LTCDecoder.syncWord else { return nil }
        guard frameBitsCount >= 80 else {
            frameBitsHead = 0
            frameBitsCount = 0
            return nil
        }

        // Extract last 80 bits from circular buffer
        var frameData = [UInt8](repeating: 0, count: 80)
        let start = (frameBitsHead + frameBitsCount - 80) % 160
        for i in 0..<80 {
            frameData[i] = frameBits[(start + i) % 160]
        }
        let frameDurationSamples = UInt64(estimatedBitDuration * 80.0)
        let startSample = absoluteSamplePos > frameDurationSamples
            ? absoluteSamplePos - frameDurationSamples : 0

        let frame = parseFrame(bits: frameData, startSample: startSample)
        frameBitsHead = 0
        frameBitsCount = 0
        consecutiveGoodFrames += 1
        lastDecodeTime = CFAbsoluteTimeGetCurrent()
        return frame
    }

    // MARK: - Frame Parsing (SMPTE 12M-1)

    private func parseFrame(bits: [UInt8], startSample: UInt64) -> LTCFrame {
        func extract(_ range: ClosedRange<Int>) -> Int {
            var value = 0
            for (i, bitPos) in range.enumerated() {
                if bits[bitPos] != 0 { value |= (1 << i) }
            }
            return value
        }

        let frameUnits = extract(0...3)
        let frameTens = extract(8...9)
        let frames = frameTens * 10 + frameUnits

        let secUnits = extract(16...19)
        let secTens = extract(24...26)
        let seconds = secTens * 10 + secUnits

        let minUnits = extract(32...35)
        let minTens = extract(40...42)
        let minutes = minTens * 10 + minUnits

        let hrUnits = extract(48...51)
        let hrTens = extract(56...57)
        let hours = hrTens * 10 + hrUnits

        let dropFrame = bits[10] != 0
        let colorFrame = bits[11] != 0

        var userBits: UInt32 = 0
        let userBitRanges = [4...7, 12...15, 20...23, 28...31, 36...39, 44...47, 52...55, 60...63]
        for (group, range) in userBitRanges.enumerated() {
            let nibble = UInt32(extract(range))
            userBits |= (nibble << (group * 4))
        }

        let rawFPS = sampleRate / (estimatedBitDuration * 80.0)
        let quantizedFPS = LTCDecoder.quantizeFrameRate(rawFPS, dropFrame: dropFrame)

        let maxFrames = dropFrame ? 29 : Int(quantizedFPS.rounded()) - 1
        let tc = Timecode(
            hours: min(hours, 23),
            minutes: min(minutes, 59),
            seconds: min(seconds, 59),
            frames: min(frames, max(maxFrames, 23))
        )

        return LTCFrame(
            timecode: tc,
            samplePosition: startSample,
            dropFrame: dropFrame,
            colorFrame: colorFrame,
            frameRate: quantizedFPS,
            userBits: userBits
        )
    }

    // MARK: - Frame Rate Quantization

    /// Snap a raw estimated frame rate to the nearest standard SMPTE rate.
    public static func quantizeFrameRate(_ raw: Double, dropFrame: Bool) -> Double {
        if raw < 23.99 {
            return 23.976
        } else if raw < 24.5 {
            return 24.0
        } else if raw < 27.0 {
            return 25.0
        } else {
            return dropFrame ? 29.97 : 30.0
        }
    }

    // MARK: - Adaptive Timing

    private func updateBitDurationEstimate(_ measured: Double) {
        if measured < estimatedBitDuration * 0.5 || measured > estimatedBitDuration * 2.0 {
            return
        }
        estimatedBitDuration = estimatedBitDuration * 0.9 + measured * 0.1
    }
}
