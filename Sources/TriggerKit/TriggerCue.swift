//
//  TriggerCue.swift
//  TriggerKit
//
//  Protocol for cues that can be triggered by timecode.
//

import Foundation
import TimecodeKit

/// A cue that can be triggered when timecode crosses its start point.
public protocol TriggerCue {
    /// Unique identifier for this cue.
    var cueID: UUID { get }
    /// The timecode at which this cue triggers.
    var startTimecode: Timecode { get }
    /// The timecode at which this cue's range ends (nil = use next cue's start).
    var endTimecode: Timecode? { get }
    /// Display name for logging.
    var displayName: String { get }
    /// MIDI program change number (1-128).
    var midiProgram: Int { get }
    /// Whether this cue is enabled for triggering.
    var isEnabled: Bool { get }
}
