//
//  MeterCalculator.swift
//  MeterKit
//
//  Professional audio meter calculations: RMS, peak, dBFS, K-System.
//  All methods are stateless and thread-safe — designed for real-time audio callbacks.
//

import Foundation
import AVFoundation
import Accelerate

/// Stateless audio meter calculations following K-System standards.
public struct MeterCalculator {

    /// Clip threshold: -0.1 dBFS = 0.9886 linear.
    public static let clipThreshold: Float = 0.9886

    /// Silence floor for dB conversion (-60 dBFS).
    public static let silenceFloor: Float = 0.001

    /// Silence floor in dB.
    public static let silenceDB: Float = -60.0

    /// Calculated meter values for a single channel.
    public struct MeterData: Sendable {
        public let rms: Float
        public let peak: Float
        public let clipped: Bool

        public var rmsLinear: Float { powf(10.0, rms / 20.0) }
        public var peakLinear: Float { powf(10.0, peak / 20.0) }

        public init(rms: Float, peak: Float, clipped: Bool) {
            self.rms = rms
            self.peak = peak
            self.clipped = clipped
        }
    }

    /// Calculate RMS, peak, and clip detection for a single channel buffer.
    public static func calculateMeters(
        from channelData: UnsafePointer<Float>,
        frameLength: Int,
        clipThreshold: Float = MeterCalculator.clipThreshold
    ) -> MeterData {
        guard frameLength > 0 else {
            return MeterData(rms: silenceDB, peak: silenceDB, clipped: false)
        }

        var meanSquare: Float = 0.0
        var peak: Float = 0.0

        vDSP_measqv(channelData, 1, &meanSquare, vDSP_Length(frameLength))
        vDSP_maxmgv(channelData, 1, &peak, vDSP_Length(frameLength))

        let clipped = peak >= clipThreshold
        let rms = sqrtf(meanSquare)

        let rmsDB = 20.0 * log10f(max(rms, silenceFloor))
        let peakDB = 20.0 * log10f(max(peak, silenceFloor))

        return MeterData(rms: rmsDB, peak: peakDB, clipped: clipped)
    }

    /// Calculate meters for all channels in a multichannel buffer.
    public static func calculateAllChannels(
        from buffer: AVAudioPCMBuffer,
        clipThreshold: Float = MeterCalculator.clipThreshold
    ) -> [MeterData] {
        guard let channelData = buffer.floatChannelData else {
            return silenceMeters(channelCount: Int(buffer.format.channelCount))
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return [] }

        var results: [MeterData] = []
        results.reserveCapacity(channelCount)

        for ch in 0..<channelCount {
            results.append(calculateMeters(from: channelData[ch], frameLength: frameLength, clipThreshold: clipThreshold))
        }

        return results
    }

    /// Convert dB value to normalized K-System scale (0.0 = -60dB, 1.0 = 0dB).
    public static func normalizeForKSystem(_ db: Float) -> Float {
        max(0.0, min(1.0, (db + 60.0) / 60.0))
    }

    /// K-System color zone for a given dB level.
    public static func getColorZone(_ db: Float) -> ColorZone {
        if db >= -10.0 { return .red }
        if db >= -18.0 { return .orange }
        if db >= -24.0 { return .yellow }
        return .green
    }

    /// K-System color zone identifiers.
    public enum ColorZone: Sendable {
        case green, yellow, orange, red
    }

    private static func silenceMeters(channelCount: Int) -> [MeterData] {
        guard channelCount > 0 else { return [] }
        return Array(repeating: MeterData(rms: silenceDB, peak: silenceDB, clipped: false), count: channelCount)
    }
}
