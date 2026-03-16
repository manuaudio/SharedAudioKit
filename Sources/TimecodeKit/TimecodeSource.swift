//
//  TimecodeSource.swift
//  TimecodeKit
//
//  Protocol for any object that provides a timecode stream.
//  Used by TimecodeRouter to select the best active source.
//

import Foundation

/// A source of timecode data with liveness tracking.
///
/// Conformers: LTCDecoder, MTCDecoder, InternalClock (via wrapper types in their modules).
/// The router polls `isActive` and `priority` to choose the best source.
public protocol TimecodeSource: AnyObject {
    /// Unique identifier for this source (e.g., "ltc", "mtc", "internal").
    var sourceID: String { get }

    /// The most recently decoded timecode.
    var currentTimecode: Timecode { get }

    /// The frame rate of the current timecode stream.
    var currentRate: FrameRate { get }

    /// Whether this source has received valid timecode recently.
    /// Implementations should return false if no valid data arrived within a timeout
    /// (typically 0.5s for LTC, 1.0s for MTC).
    var isActive: Bool { get }

    /// Priority for source selection. Higher values are preferred.
    /// When multiple sources are active, the router picks the one with highest priority.
    var priority: Int { get set }
}
