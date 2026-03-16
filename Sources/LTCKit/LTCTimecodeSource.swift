//
//  LTCTimecodeSource.swift
//  LTCKit
//
//  Bridges LTCDecoder to the TimecodeSource protocol for use with TimecodeRouter.
//

import Foundation
import TimecodeKit

/// TimecodeSource wrapper for LTCDecoder.
///
/// After calling `decoder.decode()`, pass the results to `update(frames:)` to
/// cache the latest timecode/rate for the router to poll.
public final class LTCTimecodeSource: TimecodeSource {
    public let sourceID: String
    public var priority: Int
    private let decoder: LTCDecoder

    private var lastTimecode: Timecode = .zero
    private var lastRate: FrameRate = .fps30

    public init(decoder: LTCDecoder, sourceID: String = "ltc", priority: Int = 10) {
        self.decoder = decoder
        self.sourceID = sourceID
        self.priority = priority
    }

    public var currentTimecode: Timecode { lastTimecode }
    public var currentRate: FrameRate { lastRate }
    public var isActive: Bool { decoder.isActive }

    /// Call after each `decoder.decode()` pass to cache the latest frame values.
    public func update(frames: [LTCFrame]) {
        guard let last = frames.last else { return }
        lastTimecode = last.timecode
        lastRate = last.quantizedRate
    }
}
