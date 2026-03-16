//
//  Timecode.swift
//  TimecodeKit
//
//  SMPTE timecode value. Four fields: hours, minutes, seconds, frames.
//  Stores an optional frame rate for convenience (TC Trigger style).
//  Rate-agnostic methods (pass FrameRate as parameter) also available.
//

import Foundation

/// A SMPTE timecode value (HH:MM:SS:FF).
///
/// The struct stores a `frameRate` for convenience (defaults to `.fps30`).
/// Rate-agnostic methods that accept a `FrameRate` parameter are also provided
/// for apps that keep rate separate (RecSync style).
///
/// Equatable and Hashable compare only (h, m, s, f) — not the stored rate —
/// so timecodes at different rates with the same fields compare as equal.
public struct Timecode: Codable, Sendable {
    public var hours: Int
    public var minutes: Int
    public var seconds: Int
    public var frames: Int
    public var frameRate: FrameRate

    public init(hours: Int, minutes: Int, seconds: Int, frames: Int, frameRate: FrameRate) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.frameRate = frameRate
    }

    /// Convenience init without frame rate (defaults to .fps30).
    public init(hours: Int = 0, minutes: Int = 0, seconds: Int = 0, frames: Int = 0) {
        self.init(hours: hours, minutes: minutes, seconds: seconds, frames: frames, frameRate: .fps30)
    }

    /// The zero timecode (00:00:00:00).
    public static let zero = Timecode()

    /// Components without frame rate.
    public var components: TimecodeComponents {
        TimecodeComponents(hours: hours, minutes: minutes, seconds: seconds, frames: frames)
    }

    /// Formatted display string: "HH:MM:SS:FF".
    public var displayString: String {
        String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    /// For compatibility with existing code that uses .description
    public var description: String { displayString }

    // MARK: - Stored-Rate API (uses stored frameRate)

    /// Linear frame count using the stored frame rate.
    public var totalFrames: Int {
        toFrames(rate: frameRate)
    }

    /// Create a Timecode from components and frame rate.
    public static func from(components: TimecodeComponents, frameRate: FrameRate) -> Timecode {
        Timecode(hours: components.hours, minutes: components.minutes,
                 seconds: components.seconds, frames: components.frames, frameRate: frameRate)
    }

    /// Convert frame count back to Timecode using the stored-rate style.
    public static func fromFrames(_ total: Int, frameRate: FrameRate) -> Timecode {
        fromFrames(total, fps: frameRate.fps, dropFrame: frameRate.isDropFrame, storedRate: frameRate)
    }

    /// Add/subtract frames using the stored frame rate.
    public func adding(frames offset: Int) -> Timecode {
        let newTotal = max(0, totalFrames + offset)
        return Timecode.fromFrames(newTotal, frameRate: frameRate)
    }

    /// Signed frame distance using stored frame rates.
    public func distance(to other: Timecode) -> Int {
        other.totalFrames - totalFrames
    }

    /// Parse a timecode string with an explicit frame rate.
    public static func parse(_ string: String, frameRate: FrameRate) -> Timecode? {
        guard let tc = parse(string) else { return nil }
        return Timecode(hours: tc.hours, minutes: tc.minutes,
                        seconds: tc.seconds, frames: tc.frames, frameRate: frameRate)
    }

    // MARK: - Frame Conversion (FrameRate API)

    /// Convert to linear frame count, accounting for drop-frame if applicable.
    public func toFrames(rate: FrameRate) -> Int {
        toFrames(fps: rate.fps, dropFrame: rate.isDropFrame)
    }

    /// Convert linear frame count back to timecode.
    public static func fromFrames(_ total: Int, rate: FrameRate) -> Timecode {
        fromFrames(total, frameRate: rate)
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
        let rate = FrameRate(fps: fps, dropFrame: dropFrame)
        return fromFrames(total, fps: fps, dropFrame: dropFrame, storedRate: rate)
    }

    /// Add/subtract frames with proper rollover handling.
    public func adding(frames offset: Int, fps: Int, dropFrame: Bool = false) -> Timecode {
        Timecode.fromFrames(toFrames(fps: fps, dropFrame: dropFrame) + offset, fps: fps, dropFrame: dropFrame)
    }

    // MARK: - Parsing

    /// Parse a timecode string "HH:MM:SS:FF". Returns nil if invalid.
    /// The returned Timecode has a default frame rate of .fps30.
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

    // MARK: - Internal

    private static func fromFrames(_ total: Int, fps: Int, dropFrame: Bool, storedRate: FrameRate) -> Timecode {
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
                // Non-tenth minutes skip frames 0,1 at second 0.
                // Add them back so s/f math produces correct display values.
                remainder += 2
            }

            let totalMinutes = tenMinBlocks * 10 + mins
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            let s = remainder / 30
            let f = remainder % 30

            return Timecode(hours: h, minutes: m, seconds: s, frames: f, frameRate: storedRate)
        }

        let h = r / (3600 * fps); r %= (3600 * fps)
        let m = r / (60 * fps);   r %= (60 * fps)
        let s = r / fps
        let f = r % fps
        return Timecode(hours: h, minutes: m, seconds: s, frames: f, frameRate: storedRate)
    }

    // MARK: - Codable (handles missing frameRate for backwards compatibility)

    private enum CodingKeys: String, CodingKey {
        case hours, minutes, seconds, frames, frameRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hours = try container.decode(Int.self, forKey: .hours)
        minutes = try container.decode(Int.self, forKey: .minutes)
        seconds = try container.decode(Int.self, forKey: .seconds)
        frames = try container.decode(Int.self, forKey: .frames)
        frameRate = try container.decodeIfPresent(FrameRate.self, forKey: .frameRate) ?? .fps30
    }
}

// MARK: - Equatable & Hashable (compare h/m/s/f only, not stored rate)

extension Timecode: Equatable {
    public static func == (lhs: Timecode, rhs: Timecode) -> Bool {
        lhs.hours == rhs.hours &&
        lhs.minutes == rhs.minutes &&
        lhs.seconds == rhs.seconds &&
        lhs.frames == rhs.frames
    }
}

extension Timecode: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hours)
        hasher.combine(minutes)
        hasher.combine(seconds)
        hasher.combine(frames)
    }
}
