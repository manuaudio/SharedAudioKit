//
//  TimecodeComponents.swift
//  TimecodeKit
//
//  Lightweight container for hours, minutes, seconds, frames
//  without a stored frame rate. Useful for storing cue positions
//  separately from frame rate (apply rate at evaluation time).
//

import Foundation

/// Rate-less timecode container (HH:MM:SS:FF without stored frame rate).
///
/// Use this when you need to store a timecode position independently
/// of the frame rate. Convert to `Timecode` with `toTimecode(frameRate:)`.
public struct TimecodeComponents: Codable, Equatable, Sendable {
    public var hours: Int
    public var minutes: Int
    public var seconds: Int
    public var frames: Int

    public init(hours: Int, minutes: Int, seconds: Int, frames: Int) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
    }

    /// Clamp fields to valid ranges for the given frame rate.
    public func validated(for frameRate: FrameRate) -> TimecodeComponents {
        let maxFrames = frameRate.framesPerSecond - 1
        return TimecodeComponents(
            hours: max(0, min(23, hours)),
            minutes: max(0, min(59, minutes)),
            seconds: max(0, min(59, seconds)),
            frames: max(0, min(maxFrames, frames))
        )
    }

    /// Convert to a full Timecode with the given frame rate.
    public func toTimecode(frameRate: FrameRate) -> Timecode {
        Timecode.from(components: self, frameRate: frameRate)
    }
}
