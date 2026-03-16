//
//  CueTriggerEngine.swift
//  TriggerKit
//
//  Generic edge-triggered timecode cue engine.
//  Given a current timecode and a list of cues, determines which cues to fire.
//  Handles hysteresis, forward-crossing detection, and pre-computed ranges.
//

import Foundation
import TimecodeKit

/// Pre-computed cue range for fast lookup.
public struct CueRange: Sendable {
    public let startFrames: Int
    public let endFrames: Int
    public let cueID: UUID
    public let displayName: String
    public let midiProgram: Int
    public let cueIndex: Int

    public init(startFrames: Int, endFrames: Int, cueID: UUID,
                displayName: String, midiProgram: Int, cueIndex: Int) {
        self.startFrames = startFrames
        self.endFrames = endFrames
        self.cueID = cueID
        self.displayName = displayName
        self.midiProgram = midiProgram
        self.cueIndex = cueIndex
    }
}

/// Trigger event returned when a cue fires.
public struct TriggerEvent: Sendable {
    public let cueID: UUID
    public let displayName: String
    public let midiProgram: Int
    public let cueIndex: Int
    public let rangeIndex: Int
}

/// Edge-triggered timecode cue engine.
///
/// Call `loadCues()` with your cue list, then call `evaluate()` at your
/// polling rate (typically 30Hz). The engine returns trigger events for
/// cues whose range the timecode has entered.
public final class CueTriggerEngine {

    /// Called when a cue is triggered.
    public var onCueTriggered: ((TriggerEvent) -> Void)?

    private var cueRanges: [CueRange] = []
    private var rate: FrameRate = .fps30
    private var lastTriggeredCueID: UUID?
    private var lastTriggerFrame: Int = -100
    private let hysteresisFrames = 2

    /// Max frame sentinel.
    private var maxFrames: Int { 24 * 3600 * rate.fps - 1 }

    public init() {}

    // MARK: - Load Cues

    /// Load cues and pre-compute ranges for fast lookup.
    public func loadCues(_ cues: [any TriggerCue], rate: FrameRate) {
        self.rate = rate
        self.lastTriggeredCueID = nil
        self.lastTriggerFrame = -100
        cueRanges.removeAll()

        var eligible: [(index: Int, cue: any TriggerCue, startFrames: Int)] = []
        for (i, cue) in cues.enumerated() {
            guard cue.isEnabled else { continue }
            eligible.append((i, cue, cue.startTimecode.toFrames(rate: rate)))
        }

        eligible.sort { $0.startFrames < $1.startFrames }

        for (j, entry) in eligible.enumerated() {
            let endFrames: Int
            if let endTC = entry.cue.endTimecode {
                endFrames = endTC.toFrames(rate: rate)
            } else if j + 1 < eligible.count {
                endFrames = eligible[j + 1].startFrames
            } else {
                endFrames = maxFrames
            }
            guard endFrames > entry.startFrames else { continue }

            cueRanges.append(CueRange(
                startFrames: entry.startFrames,
                endFrames: endFrames,
                cueID: entry.cue.cueID,
                displayName: entry.cue.displayName,
                midiProgram: entry.cue.midiProgram,
                cueIndex: entry.index
            ))
        }
    }

    /// Load pre-computed ranges directly.
    public func loadRanges(_ ranges: [CueRange], rate: FrameRate) {
        self.rate = rate
        self.lastTriggeredCueID = nil
        self.lastTriggerFrame = -100
        self.cueRanges = ranges
    }

    // MARK: - Evaluate

    /// Evaluate the current timecode against loaded cues.
    /// Returns the trigger event if a new cue was entered, nil otherwise.
    @discardableResult
    public func evaluate(currentTimecode: Timecode) -> TriggerEvent? {
        let liveFrames = currentTimecode.toFrames(rate: rate)

        for (rangeIdx, range) in cueRanges.enumerated() {
            if liveFrames >= range.startFrames && liveFrames < range.endFrames {
                if lastTriggeredCueID != range.cueID {
                    let frameDelta = abs(liveFrames - lastTriggerFrame)
                    if frameDelta < hysteresisFrames && lastTriggeredCueID != nil {
                        return nil
                    }

                    lastTriggeredCueID = range.cueID
                    lastTriggerFrame = liveFrames

                    let event = TriggerEvent(
                        cueID: range.cueID,
                        displayName: range.displayName,
                        midiProgram: range.midiProgram,
                        cueIndex: range.cueIndex,
                        rangeIndex: rangeIdx
                    )
                    onCueTriggered?(event)
                    return event
                }
                return nil
            }
        }

        if lastTriggeredCueID != nil {
            lastTriggeredCueID = nil
        }
        return nil
    }

    /// Reset trigger state (clears last-triggered tracking).
    public func reset() {
        lastTriggeredCueID = nil
        lastTriggerFrame = -100
        cueRanges.removeAll()
    }

    /// The current loaded ranges (read-only).
    public var ranges: [CueRange] { cueRanges }

    /// Number of the next cue after the given range index, or nil.
    public func nextCue(afterRangeIndex idx: Int) -> CueRange? {
        idx + 1 < cueRanges.count ? cueRanges[idx + 1] : nil
    }
}
