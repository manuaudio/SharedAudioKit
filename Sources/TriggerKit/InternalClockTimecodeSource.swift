//
//  InternalClockTimecodeSource.swift
//  TriggerKit
//
//  Bridges InternalClock to the TimecodeSource protocol for use with TimecodeRouter.
//

import Foundation
import TimecodeKit

/// TimecodeSource wrapper for InternalClock.
///
/// Call `bind(to:)` from the main actor to connect to a clock instance.
/// The wrapper caches timecode values from the clock's `onTimecode` callback
/// so the router can poll them.
public final class InternalClockTimecodeSource: TimecodeSource {
    public let sourceID: String
    public var priority: Int

    private var _timecode: Timecode = .zero
    private var _rate: FrameRate = .fps30
    private var _isActive: Bool = false

    public init(sourceID: String = "internal", priority: Int = 1) {
        self.sourceID = sourceID
        self.priority = priority
    }

    public var currentTimecode: Timecode { _timecode }
    public var currentRate: FrameRate { _rate }
    public var isActive: Bool { _isActive }

    /// Bind this source to an InternalClock instance. Must be called from main actor.
    @MainActor
    public func bind(to clock: InternalClock) {
        _rate = clock.rate
        _isActive = clock.isRunning
        let previousCallback = clock.onTimecode
        clock.onTimecode = { [weak self] tc in
            self?._timecode = tc
            self?._isActive = true
            previousCallback?(tc)
        }
    }

    /// Manually mark the source as inactive (e.g., when the clock stops).
    public func markInactive() {
        _isActive = false
    }
}
