//
//  LTCTimecodeSource.swift
//  LTCKit
//
//  Bridges LTCDecoder to the TimecodeSource protocol for use with TimecodeRouter.
//

import Foundation
import os
import TimecodeKit

/// TimecodeSource wrapper for LTCDecoder.
///
/// After calling `decoder.decode()`, pass the results to `update(frames:)` to
/// cache the latest timecode/rate for the router to poll.
///
/// Thread-safe: `update()` can be called from the audio thread while
/// the router reads `currentTimecode`/`currentRate` from the main thread.
public final class LTCTimecodeSource: TimecodeSource {
    public let sourceID: String
    public var priority: Int
    private let decoder: LTCDecoder

    private var lock = os_unfair_lock()
    private var lastTimecode: Timecode = .zero
    private var lastRate: FrameRate = .fps30

    public init(decoder: LTCDecoder, sourceID: String = "ltc", priority: Int = 10) {
        self.decoder = decoder
        self.sourceID = sourceID
        self.priority = priority
    }

    public var currentTimecode: Timecode {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return lastTimecode
    }

    public var currentRate: FrameRate {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return lastRate
    }

    public var isActive: Bool { decoder.isActive }

    /// Call after each `decoder.decode()` pass to cache the latest frame values.
    public func update(frames: [LTCFrame]) {
        guard let last = frames.last else { return }
        os_unfair_lock_lock(&lock)
        lastTimecode = last.timecode
        lastRate = last.quantizedRate
        os_unfair_lock_unlock(&lock)
    }
}
