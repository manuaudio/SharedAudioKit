//
//  Timecode.swift
//  TimecodeKit
//
//  SMPTE timecode value. Four fields: hours, minutes, seconds, frames.
//  All frame-rate math is stateless — pass a FrameRate to each method.
//  The struct itself stores no rate, keeping Codable shape stable.
//

import Foundation

/// A SMPTE timecode value (HH:MM:SS:FF).
///
/// The struct is rate-agnostic — frame rate is passed as a parameter to
/// conversion methods. This keeps the Codable representation stable:
/// existing serialized Timecode values decode without migration.
public struct Timecode: Codable, Equatable, Hashable, Sendable {
    public var hours: Int
    public var minutes: Int
    public var seconds: Int
    public var frames: Int

    public init(hours: Int = 0, minutes: Int = 0, seconds: Int = 0, frames: Int = 0) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
    }

    /// The zero timecode (00:00:00:00).
    public static let zero = Timecode()

    /// Formatted display string: "HH:MM:SS:FF".
    public var displayString: String {
        String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    // For compatibility with existing code that uses .description
    public var description: String { displayString }

    // MARK: - Frame Conversion (FrameRate API)

    /// Convert to linear frame count, accounting for drop-frame if applicable.
    public func toFrames(rate: FrameRate) -> Int {
        toFrames(fps: rate.fps, dropFrame: rate.isDropFrame)
    }

    /// Convert linear frame count back to timecode.
    public static func fromFrames(_ total: Int, rate: FrameRate) -> Timecode {
        fromFrames(total, fps: rate.fps, dropFrame: rate.isDropFrame)
    }

    /// Add or subtract frames with proper rollover handling.
    public func adding(frames offset: Int, rate: FrameRate) -> Timecode {
        Timecode.fromFrames(toFrames(rate: rate) + offset, rate: rate)
    }

    /// Signed frame distance from self to other.
    public func distance(to other: Timecode, rate: FrameRate) -> Int {
        other.toFrames(rate: rate) - toFrames(rate: rate)
    }

    // MARK: - Frame Conversion (Legacy Int+Bool API)

    /// Convert to linear frame count. For 29.97 DF (fps=30, dropFrame=true),
    /// accounts for the 2 frames skipped at each minute except every 10th.
    public func toFrames(fps: Int, dropFrame: Bool = false) -> Int {
        if dropFrame && fps == 30 {
            let totalMinutes = hours * 60 + minutes
            let d = totalMinutes - totalMinutes / 10
            return hours * 3600 * 30 + minutes * 60 * 30 + seconds * 30 + frames - d * 2
        }
        return hours * 3600 * fps + minutes * 60 * fps + seconds * fps + frames
    }

    /// Convert linear frame count back to timecode.
    public static func fromFrames(_ total: Int, fps: Int, dropFrame: Bool = false) -> Timecode {
        var r = max(0, total)
        if dropFrame && fps == 30 {
            let framesPerTenMin = 10 * 60 * 30 - 9 * 2  // 17982
            let tenMinBlocks = r / framesPerTenMin
            var remainder = r % framesPerTenMin

            var mins: Int
            if remainder < 1800 {
                mins = 0
            } else {
                remainder -= 1800
                let framesPerMin = 60 * 30 - 2  // 1798
                mins = 1 + remainder / framesPerMin
                remainder = remainder % framesPerMin
            }

            let totalMinutes = tenMinBlocks * 10 + mins
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            let s = remainder / 30
            let f = remainder % 30

            return Timecode(hours: h, minutes: m, seconds: s, frames: f)
        }

        let h = r / (3600 * fps); r %= (3600 * fps)
        let m = r / (60 * fps);   r %= (60 * fps)
        let s = r / fps
        let f = r % fps
        return Timecode(hours: h, minutes: m, seconds: s, frames: f)
    }

    /// Add/subtract frames with proper rollover handling.
    public func adding(frames offset: Int, fps: Int, dropFrame: Bool = false) -> Timecode {
        Timecode.fromFrames(toFrames(fps: fps, dropFrame: dropFrame) + offset, fps: fps, dropFrame: dropFrame)
    }

    // MARK: - Parsing

    /// Parse a timecode string "HH:MM:SS:FF". Returns nil if invalid.
    public static func parse(_ string: String) -> Timecode? {
        let parts = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":").map { String($0) }
        guard parts.count == 4,
              let h = Int(parts[0]), let m = Int(parts[1]),
              let s = Int(parts[2]), let f = Int(parts[3]) else { return nil }
        guard h >= 0 && h <= 23,
              m >= 0 && m <= 59,
              s >= 0 && s <= 59,
              f >= 0 && f <= 59 else { return nil }
        return Timecode(hours: h, minutes: m, seconds: s, frames: f)
    }

    /// Wall-clock seconds for this timecode at the given rate.
    public func realTimeSeconds(rate: FrameRate) -> Double {
        Double(toFrames(rate: rate)) / rate.realRate
    }
}
