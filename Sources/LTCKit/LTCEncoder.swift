//
//  LTCEncoder.swift
//  LTCKit
//
//  Generates SMPTE LTC (Linear Timecode) audio from timecode values.
//  Produces biphase-modulated audio at the target sample rate.
//

import Foundation
import TimecodeKit

/// Generates LTC audio samples from timecode values.
public struct LTCEncoder {

    /// Generate LTC audio from an array of timecode-at-sample-position pairs.
    ///
    /// - Parameters:
    ///   - timecodes: Array of (timecode, samplePosition) pairs defining the TC timeline.
    ///   - rate: The frame rate for encoding.
    ///   - sampleRate: Audio sample rate (e.g., 96000).
    ///   - totalSamples: Total number of output samples.
    /// - Returns: Float samples containing the LTC audio signal.
    public static func encode(
        timecodes: [(timecode: Timecode, samplePosition: Int)],
        rate: FrameRate,
        sampleRate: Double,
        totalSamples: Int
    ) -> [Float] {
        let fps = rate.fps
        let isDropFrame = rate.isDropFrame
        let samplesPerFrame = sampleRate / Double(fps)
        let samplesPerBit = samplesPerFrame / 80.0

        var output = [Float](repeating: 0, count: totalSamples)

        guard let first = timecodes.first else { return output }

        var tc = first.timecode
        var currentSampleD = Double(first.samplePosition)
        var polarity: Float = 1.0

        // Build a simple lookup: find the right TC for a given sample position
        let sorted = timecodes.sorted { $0.samplePosition < $1.samplePosition }

        while Int(currentSampleD) < totalSamples {
            let currentSample = Int(currentSampleD)

            // Look up timecode at this position
            if let match = sorted.last(where: { $0.samplePosition <= currentSample }) {
                // Interpolate forward from the matched event
                let sampleDiff = currentSample - match.samplePosition
                let frameDiff = Int(Double(sampleDiff) / samplesPerFrame)
                tc = match.timecode.adding(frames: frameDiff, fps: fps, dropFrame: isDropFrame)
            }

            let bits = encodeFrame(tc, fps: fps, dropFrame: isDropFrame)

            for bitIdx in 0..<80 {
                let bitStart = currentSample + Int(Double(bitIdx) * samplesPerBit)
                let bitMid = currentSample + Int((Double(bitIdx) + 0.5) * samplesPerBit)
                let bitEnd = currentSample + Int(Double(bitIdx + 1) * samplesPerBit)

                guard bitStart < totalSamples else { break }

                polarity = -polarity
                let clampedMid = min(bitMid, totalSamples)
                let clampedEnd = min(bitEnd, totalSamples)

                for s in max(0, bitStart)..<clampedMid {
                    output[s] = polarity * 0.8
                }

                if bits[bitIdx] == 1 {
                    polarity = -polarity
                }

                for s in max(0, clampedMid)..<clampedEnd {
                    output[s] = polarity * 0.8
                }
            }

            currentSampleD += samplesPerFrame
            tc = tc.adding(frames: 1, fps: fps, dropFrame: isDropFrame)
        }

        return output
    }

    /// Encode a single SMPTE 12M timecode value into 80 bits.
    public static func encodeFrame(_ tc: Timecode, fps: Int, dropFrame: Bool) -> [UInt8] {
        var bits = [UInt8](repeating: 0, count: 80)

        setBCD(&bits, value: tc.frames % 10, startBit: 0, count: 4)
        setBCD(&bits, value: tc.frames / 10, startBit: 8, count: 2)
        if dropFrame { bits[10] = 1 }

        setBCD(&bits, value: tc.seconds % 10, startBit: 16, count: 4)
        setBCD(&bits, value: tc.seconds / 10, startBit: 24, count: 3)

        setBCD(&bits, value: tc.minutes % 10, startBit: 32, count: 4)
        setBCD(&bits, value: tc.minutes / 10, startBit: 40, count: 3)

        setBCD(&bits, value: tc.hours % 10, startBit: 48, count: 4)
        setBCD(&bits, value: tc.hours / 10, startBit: 56, count: 2)

        let sync: [UInt8] = [0,0,1,1, 1,1,1,1, 1,1,1,1, 1,1,0,1]
        for i in 0..<16 { bits[64 + i] = sync[i] }

        return bits
    }

    private static func setBCD(_ bits: inout [UInt8], value: Int, startBit: Int, count: Int) {
        for i in 0..<count {
            bits[startBit + i] = UInt8((value >> i) & 1)
        }
    }
}
